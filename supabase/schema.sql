-- ============================================================
-- PollRoom schema — paste this whole file into the Supabase
-- SQL Editor (SQL Editor → New query → Run).
--
-- >>> BEFORE RUNNING: change the presenter passphrase below <<<
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- tables ----------

create table if not exists room (
  id            int primary key default 1 check (id = 1),
  title         text not null default 'PollRoom',
  active_poll_id uuid,
  comments_open boolean not null default true,
  updated_at    timestamptz not null default now()
);

create table if not exists room_secret (
  pass text not null
);

create table if not exists polls (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  type           text not null check (type in ('choice','words','open')),
  options        jsonb not null default '[]',
  allow_multiple boolean not null default false,
  position       int not null default 0,
  created_at     timestamptz not null default now()
);

create table if not exists votes (
  id         uuid primary key default gen_random_uuid(),
  poll_id    uuid not null references polls(id) on delete cascade,
  device_id  uuid not null,
  option_idx int not null,
  created_at timestamptz not null default now(),
  unique (poll_id, device_id, option_idx)
);

create table if not exists words (
  id         uuid primary key default gen_random_uuid(),
  poll_id    uuid not null references polls(id) on delete cascade,
  device_id  uuid not null,
  word       text not null,
  created_at timestamptz not null default now(),
  unique (poll_id, device_id, word)
);

create table if not exists messages (
  id         uuid primary key default gen_random_uuid(),
  poll_id    uuid references polls(id) on delete cascade,
  device_id  uuid not null,
  body       text not null,
  hidden     boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists upvotes (
  message_id uuid not null references messages(id) on delete cascade,
  device_id  uuid not null,
  primary key (message_id, device_id)
);

insert into room (id) values (1) on conflict do nothing;

-- >>> CHANGE THIS PASSPHRASE <<<
insert into room_secret (pass) values ('change-me-before-running');

-- ---------- row level security ----------
-- Audience devices use the public anon key. They may READ room + polls
-- directly; everything else goes through the RPC functions below or the
-- aggregate views, so raw device ids are never exposed.

alter table room        enable row level security;
alter table room_secret enable row level security;
alter table polls       enable row level security;
alter table votes       enable row level security;
alter table words       enable row level security;
alter table messages    enable row level security;
alter table upvotes     enable row level security;

create policy room_read  on room  for select using (true);
create policy polls_read on polls for select using (true);
-- (no policies on the other tables: no direct access)

revoke all on room_secret from anon, authenticated;

-- ---------- aggregate views (owned by postgres → not blocked by RLS) ----------

create or replace view vote_counts with (security_invoker = off) as
  select poll_id, option_idx, count(*)::int as n
  from votes group by 1, 2;

create or replace view word_counts with (security_invoker = off) as
  select poll_id, lower(btrim(word)) as word, count(*)::int as n
  from words group by 1, 2;

create or replace view respondent_counts with (security_invoker = off) as
  select poll_id, count(distinct device_id)::int as n from votes group by 1
  union all
  select poll_id, count(distinct device_id)::int from words group by 1;

create or replace view messages_public with (security_invoker = off) as
  select m.id, m.poll_id, m.body, m.hidden, m.created_at,
         coalesce(u.n, 0) as upvotes
  from messages m
  left join (
    select message_id, count(*)::int as n from upvotes group by 1
  ) u on u.message_id = m.id;

grant select on vote_counts, word_counts, respondent_counts, messages_public
  to anon, authenticated;

-- ---------- helpers ----------

create or replace function check_admin(_pass text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from room_secret where pass = _pass);
$$;

create or replace function _require_admin(_pass text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not check_admin(_pass) then
    raise exception 'bad passphrase';
  end if;
end $$;

create or replace function _require_active(_poll uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if (select active_poll_id from room where id = 1) is distinct from _poll then
    raise exception 'poll is not live';
  end if;
end $$;

-- ---------- audience RPCs ----------

create or replace function cast_vote(_poll uuid, _device uuid, _options int[])
returns void language plpgsql security definer set search_path = public as $$
declare
  p polls;
  n int;
begin
  select * into p from polls where id = _poll;
  if p.id is null or p.type <> 'choice' then raise exception 'invalid poll'; end if;
  perform _require_active(_poll);
  n := coalesce(array_length(_options, 1), 0);
  if n < 1 then raise exception 'pick at least one option'; end if;
  if not p.allow_multiple and n > 1 then raise exception 'single choice only'; end if;
  if exists (
    select 1 from unnest(_options) o
    where o < 0 or o >= jsonb_array_length(p.options)
  ) then
    raise exception 'invalid option';
  end if;
  delete from votes where poll_id = _poll and device_id = _device;
  insert into votes (poll_id, device_id, option_idx)
    select distinct _poll, _device, o from unnest(_options) o;
end $$;

create or replace function submit_words(_poll uuid, _device uuid, _words text[])
returns void language plpgsql security definer set search_path = public as $$
declare
  p polls;
  clean text[];
begin
  select * into p from polls where id = _poll;
  if p.id is null or p.type <> 'words' then raise exception 'invalid poll'; end if;
  perform _require_active(_poll);
  clean := array(
    select distinct btrim(w) from unnest(_words) w
    where btrim(w) <> '' and length(btrim(w)) <= 40
    limit 3
  );
  if coalesce(array_length(clean, 1), 0) = 0 then
    raise exception 'enter at least one word';
  end if;
  delete from words where poll_id = _poll and device_id = _device;
  insert into words (poll_id, device_id, word)
    select _poll, _device, w from unnest(clean) w;
end $$;

create or replace function post_message(_device uuid, _body text, _poll uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  b text := btrim(_body);
  p polls;
  new_id uuid;
begin
  if length(b) < 1 or length(b) > 280 then
    raise exception 'message must be 1-280 characters';
  end if;
  if _poll is null then
    if not (select comments_open from room where id = 1) then
      raise exception 'comments are closed';
    end if;
  else
    select * into p from polls where id = _poll;
    if p.id is null or p.type <> 'open' then raise exception 'invalid poll'; end if;
    perform _require_active(_poll);
  end if;
  insert into messages (poll_id, device_id, body)
    values (_poll, _device, b)
    returning id into new_id;
  return new_id;
end $$;

create or replace function toggle_upvote(_message uuid, _device uuid)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  delete from upvotes where message_id = _message and device_id = _device;
  if found then
    return false;
  end if;
  insert into upvotes (message_id, device_id) values (_message, _device);
  return true;
end $$;

-- ---------- presenter (admin) RPCs ----------

create or replace function admin_save_poll(
  _pass text, _id uuid, _title text, _type text,
  _options jsonb, _allow_multiple boolean
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  new_id uuid;
begin
  perform _require_admin(_pass);
  if btrim(coalesce(_title, '')) = '' then raise exception 'title required'; end if;
  if _type not in ('choice', 'words', 'open') then raise exception 'invalid type'; end if;
  if _type = 'choice' and jsonb_array_length(coalesce(_options, '[]')) < 2 then
    raise exception 'choice polls need at least 2 options';
  end if;
  if _id is null then
    insert into polls (title, type, options, allow_multiple, position)
      values (btrim(_title), _type, coalesce(_options, '[]'), coalesce(_allow_multiple, false),
              coalesce((select max(position) + 1 from polls), 0))
      returning id into new_id;
    return new_id;
  end if;
  update polls set
    title = btrim(_title), type = _type,
    options = coalesce(_options, '[]'),
    allow_multiple = coalesce(_allow_multiple, false)
    where id = _id;
  return _id;
end $$;

create or replace function admin_delete_poll(_pass text, _id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_admin(_pass);
  update room set active_poll_id = null, updated_at = now()
    where id = 1 and active_poll_id = _id;
  delete from polls where id = _id;
end $$;

create or replace function admin_set_active(_pass text, _poll uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_admin(_pass);
  update room set active_poll_id = _poll, updated_at = now() where id = 1;
end $$;

create or replace function admin_set_room(_pass text, _title text, _comments_open boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_admin(_pass);
  update room set
    title = coalesce(nullif(btrim(_title), ''), title),
    comments_open = coalesce(_comments_open, comments_open),
    updated_at = now()
    where id = 1;
end $$;

create or replace function admin_hide_message(_pass text, _id uuid, _hidden boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_admin(_pass);
  update messages set hidden = _hidden where id = _id;
end $$;

create or replace function admin_reset_poll(_pass text, _id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_admin(_pass);
  delete from votes where poll_id = _id;
  delete from words where poll_id = _id;
  delete from messages where poll_id = _id;
end $$;

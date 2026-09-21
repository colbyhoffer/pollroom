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

create table if not exists sessions (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  created_at timestamptz not null default now()
);

create table if not exists polls (
  id             uuid primary key default gen_random_uuid(),
  session_id     uuid references sessions(id) on delete cascade,
  title          text not null,
  type           text not null check (type in ('choice','words','open')),
  options        jsonb not null default '[]',
  allow_multiple boolean not null default false,
  revealed       boolean not null default false,  -- open polls: responses shown to audience?
  max_upvotes    int not null default 3,          -- per-person upvote cap on open polls; 0 = no limit
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
  session_id uuid references sessions(id) on delete cascade,
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

alter table room add column if not exists active_session_id uuid references sessions(id);

insert into room (id) values (1) on conflict do nothing;

-- start with one session and make it active
do $$
declare sid uuid;
begin
  if not exists (select 1 from sessions) then
    insert into sessions (name) values ('First session') returning id into sid;
    update room set active_session_id = sid where id = 1;
  end if;
end $$;

-- >>> CHANGE THIS PASSPHRASE <<<
insert into room_secret (pass) values ('change-me-before-running');

-- ---------- row level security ----------
-- Audience devices use the public anon key. They may READ room + polls
-- directly; everything else goes through the RPC functions below or the
-- aggregate views, so raw device ids are never exposed.

alter table room        enable row level security;
alter table room_secret enable row level security;
alter table sessions    enable row level security;
alter table polls       enable row level security;
alter table votes       enable row level security;
alter table words       enable row level security;
alter table messages    enable row level security;
alter table upvotes     enable row level security;

create policy room_read     on room     for select using (true);
create policy sessions_read on sessions for select using (true);
create policy polls_read    on polls    for select using (true);
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
         coalesce(u.n, 0) as upvotes,
         m.session_id
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
  sid uuid;
  new_id uuid;
begin
  if length(b) < 1 or length(b) > 280 then
    raise exception 'message must be 1-280 characters';
  end if;
  if _poll is null then
    if not (select comments_open from room where id = 1) then
      raise exception 'comments are closed';
    end if;
    sid := (select active_session_id from room where id = 1);
  else
    select * into p from polls where id = _poll;
    if p.id is null or p.type <> 'open' then raise exception 'invalid poll'; end if;
    perform _require_active(_poll);
    sid := p.session_id;
  end if;
  insert into messages (poll_id, device_id, body, session_id)
    values (_poll, _device, b, sid)
    returning id into new_id;
  return new_id;
end $$;

create or replace function toggle_upvote(_message uuid, _device uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  m messages;
  lim int;
  used int;
begin
  select * into m from messages where id = _message;
  if m.id is null then raise exception 'message not found'; end if;
  delete from upvotes where message_id = _message and device_id = _device;
  if found then
    return false;
  end if;
  if m.poll_id is not null then
    select max_upvotes into lim from polls where id = m.poll_id;
    if coalesce(lim, 0) > 0 then
      select count(*) into used
      from upvotes u join messages mm on mm.id = u.message_id
      where mm.poll_id = m.poll_id and u.device_id = _device;
      if used >= lim then
        raise exception 'you can only boost % % on this poll', lim, case when lim = 1 then 'response' else 'responses' end;
      end if;
    end if;
  end if;
  insert into upvotes (message_id, device_id) values (_message, _device);
  return true;
end $$;

-- ---------- presenter (admin) RPCs ----------

create or replace function admin_save_poll(
  _pass text, _id uuid, _title text, _type text,
  _options jsonb, _allow_multiple boolean, _max_upvotes int default 3
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  new_id uuid;
  lim int := greatest(coalesce(_max_upvotes, 3), 0);
begin
  perform _require_admin(_pass);
  if btrim(coalesce(_title, '')) = '' then raise exception 'title required'; end if;
  if _type not in ('choice', 'words', 'open') then raise exception 'invalid type'; end if;
  if _type = 'choice' and jsonb_array_length(coalesce(_options, '[]')) < 2 then
    raise exception 'choice polls need at least 2 options';
  end if;
  if _id is null then
    insert into polls (title, type, options, allow_multiple, max_upvotes, position, session_id)
      values (btrim(_title), _type, coalesce(_options, '[]'), coalesce(_allow_multiple, false), lim,
              coalesce((select max(position) + 1 from polls), 0),
              (select active_session_id from room where id = 1))
      returning id into new_id;
    return new_id;
  end if;
  update polls set
    title = btrim(_title), type = _type,
    options = coalesce(_options, '[]'),
    allow_multiple = coalesce(_allow_multiple, false),
    max_upvotes = lim
    where id = _id;
  return _id;
end $$;

create or replace function admin_set_revealed(_pass text, _id uuid, _revealed boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_admin(_pass);
  update polls set revealed = _revealed where id = _id;
end $$;

create or replace function admin_create_session(_pass text, _name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  perform _require_admin(_pass);
  if btrim(coalesce(_name, '')) = '' then raise exception 'session name required'; end if;
  insert into sessions (name) values (btrim(_name)) returning id into sid;
  update room set active_session_id = sid, active_poll_id = null, updated_at = now() where id = 1;
  return sid;
end $$;

create or replace function admin_set_active_session(_pass text, _id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_admin(_pass);
  if not exists (select 1 from sessions where id = _id) then
    raise exception 'no such session';
  end if;
  update room set active_session_id = _id, active_poll_id = null, updated_at = now() where id = 1;
end $$;

create or replace function admin_rename_session(_pass text, _id uuid, _name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_admin(_pass);
  if btrim(coalesce(_name, '')) = '' then raise exception 'session name required'; end if;
  update sessions set name = btrim(_name) where id = _id;
end $$;

create or replace function admin_delete_session(_pass text, _id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare fallback uuid;
begin
  perform _require_admin(_pass);
  if (select count(*) from sessions) <= 1 then
    raise exception 'cannot delete the only session';
  end if;
  delete from sessions where id = _id;  -- cascades to its polls, votes, messages
  if (select active_session_id from room where id = 1) is null
     or not exists (select 1 from sessions where id = (select active_session_id from room where id = 1)) then
    select id into fallback from sessions order by created_at desc limit 1;
    update room set active_session_id = fallback, active_poll_id = null, updated_at = now() where id = 1;
  end if;
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

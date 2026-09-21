-- ============================================================
-- Migration: poll sessions (named sets of polls + responses)
-- For projects already running the previous schema/migrations.
-- Paste the whole file into the Supabase SQL Editor and Run.
-- Your existing polls, votes, and messages are adopted into a
-- session named 'First session'.
-- ============================================================

create table if not exists sessions (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  created_at timestamptz not null default now()
);
alter table sessions enable row level security;
drop policy if exists sessions_read on sessions;
create policy sessions_read on sessions for select using (true);

alter table polls    add column if not exists session_id uuid references sessions(id) on delete cascade;
alter table messages add column if not exists session_id uuid references sessions(id) on delete cascade;
alter table room     add column if not exists active_session_id uuid references sessions(id);

-- adopt existing data into a default session
do $$
declare sid uuid;
begin
  if not exists (select 1 from sessions) then
    insert into sessions (name) values ('First session') returning id into sid;
    update polls set session_id = sid where session_id is null;
    update messages set session_id = sid where session_id is null;
    update room set active_session_id = sid where id = 1;
  end if;
end $$;

-- expose session_id on the public messages view (appended column)
create or replace view messages_public with (security_invoker = off) as
  select m.id, m.poll_id, m.body, m.hidden, m.created_at,
         coalesce(u.n, 0) as upvotes,
         m.session_id
  from messages m
  left join (
    select message_id, count(*)::int as n from upvotes group by 1
  ) u on u.message_id = m.id;

-- new polls land in the active session
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

-- messages are stamped with their session
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

-- ---------- session management (presenter) ----------

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

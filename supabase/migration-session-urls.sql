-- ============================================================
-- Migration: per-session URLs (?s=<slug>) + async polls open from any
-- session's page + chat posts into the session being viewed
-- For projects already running the previous schema/migrations.
-- Paste the whole file into the Supabase SQL Editor and Run.
-- ============================================================

alter table sessions add column if not exists slug text;

create or replace function _session_slug(_name text, _self uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  base text;
  cand text;
  n int := 1;
begin
  base := btrim(lower(regexp_replace(coalesce(_name, ''), '[^a-zA-Z0-9]+', '-', 'g')), '-');
  if base = '' then base := 'session'; end if;
  cand := base;
  while exists (select 1 from sessions where slug = cand and (_self is null or id <> _self)) loop
    n := n + 1;
    cand := base || '-' || n;
  end loop;
  return cand;
end $$;

update sessions set slug = _session_slug(name, id) where slug is null;
create unique index if not exists sessions_slug_key on sessions (slug);

-- the frontend now passes _session on chat posts; drop the older 3-argument version
drop function if exists post_message(uuid, text, uuid);

create or replace function _require_active(_poll uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  r room;
  p polls;
begin
  select * into r from room where id = 1;
  if r.active_poll_id = _poll then return; end if;
  select * into p from polls where id = _poll;
  if r.active_group is not null
     and p.group_name = r.active_group
     and p.session_id = r.active_session_id then
    return;
  end if;
  if p.async_open then
    return;  -- open-anytime polls are answerable from any session's URL
  end if;
  raise exception 'poll is not live';
end $$;

create or replace function post_message(_device uuid, _body text, _poll uuid default null, _session uuid default null)
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
    if _session is not null and not exists (select 1 from sessions where id = _session) then
      raise exception 'no such session';
    end if;
    sid := coalesce(_session, (select active_session_id from room where id = 1));
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

create or replace function admin_create_session(_pass text, _name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  perform _require_admin(_pass);
  if btrim(coalesce(_name, '')) = '' then raise exception 'session name required'; end if;
  insert into sessions (name, theme, slug)
    values (btrim(_name),
            coalesce((select theme from sessions where id = (select active_session_id from room where id = 1)), 'default'),
            _session_slug(_name, null))
    returning id into sid;
  update room set active_session_id = sid, active_poll_id = null, updated_at = now() where id = 1;
  return sid;
end $$;

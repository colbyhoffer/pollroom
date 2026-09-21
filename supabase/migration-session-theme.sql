-- ============================================================
-- Migration: theme moves from the room to each session
-- For projects already running the previous schema/migrations.
-- Paste the whole file into the Supabase SQL Editor and Run.
-- Existing sessions adopt the room's current theme.
-- ============================================================

alter table sessions add column if not exists theme text not null default 'default';
update sessions set theme = coalesce((select theme from room where id = 1), 'default');

create or replace function admin_set_session_theme(_pass text, _id uuid, _theme text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_admin(_pass);
  if btrim(coalesce(_theme, '')) = '' then raise exception 'theme required'; end if;
  update sessions set theme = btrim(_theme) where id = _id;
end $$;

-- new sessions inherit the active session's theme
create or replace function admin_create_session(_pass text, _name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  perform _require_admin(_pass);
  if btrim(coalesce(_name, '')) = '' then raise exception 'session name required'; end if;
  insert into sessions (name, theme)
    values (btrim(_name),
            coalesce((select theme from sessions where id = (select active_session_id from room where id = 1)), 'default'))
    returning id into sid;
  update room set active_session_id = sid, active_poll_id = null, updated_at = now() where id = 1;
  return sid;
end $$;

-- ============================================================
-- Migration: room theme (restyles all surfaces from themes.js)
-- For projects already running the previous schema/migrations.
-- Paste the whole file into the Supabase SQL Editor and Run.
-- ============================================================

alter table room add column if not exists theme text not null default 'default';

-- the frontend now passes _theme; drop the older 3-argument version
-- so PostgREST doesn't see two overloads
drop function if exists admin_set_room(text, text, boolean);

create or replace function admin_set_room(_pass text, _title text, _comments_open boolean, _theme text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_admin(_pass);
  update room set
    title = coalesce(nullif(btrim(_title), ''), title),
    comments_open = coalesce(_comments_open, comments_open),
    theme = coalesce(nullif(btrim(_theme), ''), theme),
    updated_at = now()
    where id = 1;
end $$;

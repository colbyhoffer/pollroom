-- ============================================================
-- Migration: optional subtitle on polls
-- For projects already running the previous schema/migrations.
-- Paste the whole file into the Supabase SQL Editor and Run.
-- ============================================================

alter table polls add column if not exists subtitle text;

-- the frontend now passes _subtitle; drop the older 7-argument version
-- so PostgREST doesn't see two overloads
drop function if exists admin_save_poll(text, uuid, text, text, jsonb, boolean, int);

create or replace function admin_save_poll(
  _pass text, _id uuid, _title text, _type text,
  _options jsonb, _allow_multiple boolean, _max_upvotes int default 3,
  _subtitle text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  new_id uuid;
  lim int := greatest(coalesce(_max_upvotes, 3), 0);
  sub text := nullif(btrim(coalesce(_subtitle, '')), '');
begin
  perform _require_admin(_pass);
  if btrim(coalesce(_title, '')) = '' then raise exception 'title required'; end if;
  if _type not in ('choice', 'words', 'open') then raise exception 'invalid type'; end if;
  if _type = 'choice' and jsonb_array_length(coalesce(_options, '[]')) < 2 then
    raise exception 'choice polls need at least 2 options';
  end if;
  if _id is null then
    insert into polls (title, subtitle, type, options, allow_multiple, max_upvotes, position, session_id)
      values (btrim(_title), sub, _type, coalesce(_options, '[]'), coalesce(_allow_multiple, false), lim,
              coalesce((select max(position) + 1 from polls), 0),
              (select active_session_id from room where id = 1))
      returning id into new_id;
    return new_id;
  end if;
  update polls set
    title = btrim(_title), subtitle = sub, type = _type,
    options = coalesce(_options, '[]'),
    allow_multiple = coalesce(_allow_multiple, false),
    max_upvotes = lim
    where id = _id;
  return _id;
end $$;

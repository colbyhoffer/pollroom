-- ============================================================
-- Migration: "open anytime" polls (answerable without presenting)
-- For projects already running the previous schema/migrations.
-- Paste the whole file into the Supabase SQL Editor and Run.
-- ============================================================

alter table polls add column if not exists async_open boolean not null default false;

-- the frontend now passes _async_open; drop the older 11-argument version
drop function if exists admin_save_poll(text, uuid, text, text, jsonb, boolean, int, text, int, text, int);

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
  if p.async_open and p.session_id = r.active_session_id then
    return;
  end if;
  raise exception 'poll is not live';
end $$;

create or replace function admin_save_poll(
  _pass text, _id uuid, _title text, _type text,
  _options jsonb, _allow_multiple boolean, _max_upvotes int default 3,
  _subtitle text default null, _timer_seconds int default 0,
  _group_name text default null, _max_words int default 3,
  _async_open boolean default false
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  new_id uuid;
  lim int := greatest(coalesce(_max_upvotes, 3), -1);  -- -1 = upvoting off
  sub text := nullif(btrim(coalesce(_subtitle, '')), '');
  tmr int := greatest(coalesce(_timer_seconds, 0), 0);
  grp text := nullif(btrim(coalesce(_group_name, '')), '');
  wrd int := least(greatest(coalesce(_max_words, 3), 1), 3);
  asy boolean := coalesce(_async_open, false);
begin
  perform _require_admin(_pass);
  if btrim(coalesce(_title, '')) = '' then raise exception 'title required'; end if;
  if _type not in ('choice', 'words', 'open') then raise exception 'invalid type'; end if;
  if _type = 'choice' and jsonb_array_length(coalesce(_options, '[]')) < 2 then
    raise exception 'choice polls need at least 2 options';
  end if;
  if _id is null then
    insert into polls (title, subtitle, type, options, allow_multiple, max_upvotes, timer_seconds, group_name, max_words, async_open, position, session_id)
      values (btrim(_title), sub, _type, coalesce(_options, '[]'), coalesce(_allow_multiple, false), lim, tmr, grp, wrd, asy,
              coalesce((select max(position) + 1 from polls), 0),
              (select active_session_id from room where id = 1))
      returning id into new_id;
    return new_id;
  end if;
  update polls set
    title = btrim(_title), subtitle = sub, type = _type,
    options = coalesce(_options, '[]'),
    allow_multiple = coalesce(_allow_multiple, false),
    max_upvotes = lim,
    timer_seconds = tmr,
    group_name = grp,
    max_words = wrd,
    async_open = asy
    where id = _id;
  return _id;
end $$;

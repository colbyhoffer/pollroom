-- ============================================================
-- Migration: "Other…" write-in option on multiple choice polls
-- For projects already running the previous schema/migrations.
-- Paste the whole file into the Supabase SQL Editor and Run.
-- ============================================================

alter table polls add column if not exists allow_other boolean not null default false;
alter table votes add column if not exists other_text text;

create or replace view other_answers with (security_invoker = off) as
  select poll_id, other_text, created_at
  from votes
  where option_idx = -1 and other_text is not null;
grant select on other_answers to anon, authenticated;

-- the frontend now passes _other / _allow_other; drop the older versions
drop function if exists cast_vote(uuid, uuid, int[]);
drop function if exists admin_save_poll(text, uuid, text, text, jsonb, boolean, int, text, int, text, int, boolean);

create or replace function cast_vote(_poll uuid, _device uuid, _options int[], _other text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  p polls;
  n int;
  oth text := btrim(coalesce(_other, ''));
begin
  select * into p from polls where id = _poll;
  if p.id is null or p.type <> 'choice' then raise exception 'invalid poll'; end if;
  perform _require_active(_poll);
  n := coalesce(array_length(_options, 1), 0);
  if n < 1 then raise exception 'pick at least one option'; end if;
  if not p.allow_multiple and n > 1 then raise exception 'single choice only'; end if;
  if exists (
    select 1 from unnest(_options) o
    where (o < 0 or o >= jsonb_array_length(p.options))
      and not (o = -1 and p.allow_other)
  ) then
    raise exception 'invalid option';
  end if;
  if -1 = any(_options) then
    if oth = '' then raise exception 'tell us your Other answer'; end if;
    if length(oth) > 60 then raise exception 'Other answer must be 60 characters or fewer'; end if;
  end if;
  delete from votes where poll_id = _poll and device_id = _device;
  insert into votes (poll_id, device_id, option_idx, other_text)
    select distinct _poll, _device, o, case when o = -1 then oth else null end
    from unnest(_options) o;
end $$;

create or replace function admin_save_poll(
  _pass text, _id uuid, _title text, _type text,
  _options jsonb, _allow_multiple boolean, _max_upvotes int default 3,
  _subtitle text default null, _timer_seconds int default 0,
  _group_name text default null, _max_words int default 3,
  _async_open boolean default false, _allow_other boolean default false
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  new_id uuid;
  lim int := greatest(coalesce(_max_upvotes, 3), -1);  -- -1 = upvoting off
  sub text := nullif(btrim(coalesce(_subtitle, '')), '');
  tmr int := greatest(coalesce(_timer_seconds, 0), 0);
  grp text := nullif(btrim(coalesce(_group_name, '')), '');
  wrd int := least(greatest(coalesce(_max_words, 3), 1), 3);
  asy boolean := coalesce(_async_open, false);
  aot boolean := coalesce(_allow_other, false);
begin
  perform _require_admin(_pass);
  if btrim(coalesce(_title, '')) = '' then raise exception 'title required'; end if;
  if _type not in ('choice', 'words', 'open') then raise exception 'invalid type'; end if;
  if _type = 'choice' and jsonb_array_length(coalesce(_options, '[]')) < 2 then
    raise exception 'choice polls need at least 2 options';
  end if;
  if _id is null then
    insert into polls (title, subtitle, type, options, allow_multiple, allow_other, max_upvotes, timer_seconds, group_name, max_words, async_open, position, session_id)
      values (btrim(_title), sub, _type, coalesce(_options, '[]'), coalesce(_allow_multiple, false), aot, lim, tmr, grp, wrd, asy,
              coalesce((select max(position) + 1 from polls), 0),
              (select active_session_id from room where id = 1))
      returning id into new_id;
    return new_id;
  end if;
  update polls set
    title = btrim(_title), subtitle = sub, type = _type,
    options = coalesce(_options, '[]'),
    allow_multiple = coalesce(_allow_multiple, false),
    allow_other = aot,
    max_upvotes = lim,
    timer_seconds = tmr,
    group_name = grp,
    max_words = wrd,
    async_open = asy
    where id = _id;
  return _id;
end $$;

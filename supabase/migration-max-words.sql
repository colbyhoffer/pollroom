-- ============================================================
-- Migration: word clouds can limit words per person (1-3)
-- For projects already running the previous schema/migrations.
-- Paste the whole file into the Supabase SQL Editor and Run.
-- ============================================================

alter table polls add column if not exists max_words int not null default 3;

-- the frontend now passes _max_words; drop the older 10-argument version
drop function if exists admin_save_poll(text, uuid, text, text, jsonb, boolean, int, text, int, text);

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
    limit least(greatest(coalesce(p.max_words, 3), 1), 3)
  );
  if coalesce(array_length(clean, 1), 0) = 0 then
    raise exception 'enter at least one word';
  end if;
  delete from words where poll_id = _poll and device_id = _device;
  insert into words (poll_id, device_id, word)
    select _poll, _device, w from unnest(clean) w;
end $$;

create or replace function admin_save_poll(
  _pass text, _id uuid, _title text, _type text,
  _options jsonb, _allow_multiple boolean, _max_upvotes int default 3,
  _subtitle text default null, _timer_seconds int default 0,
  _group_name text default null, _max_words int default 3
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  new_id uuid;
  lim int := greatest(coalesce(_max_upvotes, 3), -1);  -- -1 = upvoting off
  sub text := nullif(btrim(coalesce(_subtitle, '')), '');
  tmr int := greatest(coalesce(_timer_seconds, 0), 0);
  grp text := nullif(btrim(coalesce(_group_name, '')), '');
  wrd int := least(greatest(coalesce(_max_words, 3), 1), 3);
begin
  perform _require_admin(_pass);
  if btrim(coalesce(_title, '')) = '' then raise exception 'title required'; end if;
  if _type not in ('choice', 'words', 'open') then raise exception 'invalid type'; end if;
  if _type = 'choice' and jsonb_array_length(coalesce(_options, '[]')) < 2 then
    raise exception 'choice polls need at least 2 options';
  end if;
  if _id is null then
    insert into polls (title, subtitle, type, options, allow_multiple, max_upvotes, timer_seconds, group_name, max_words, position, session_id)
      values (btrim(_title), sub, _type, coalesce(_options, '[]'), coalesce(_allow_multiple, false), lim, tmr, grp, wrd,
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
    max_words = wrd
    where id = _id;
  return _id;
end $$;

-- ============================================================
-- Migration: per-poll "upvoting off" (max_upvotes = -1)
-- For projects already running the previous schema/migrations.
-- Paste the whole file into the Supabase SQL Editor and Run.
-- No new columns; replaces two functions in place.
-- ============================================================

create or replace function admin_save_poll(
  _pass text, _id uuid, _title text, _type text,
  _options jsonb, _allow_multiple boolean, _max_upvotes int default 3,
  _subtitle text default null, _timer_seconds int default 0,
  _group_name text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  new_id uuid;
  lim int := greatest(coalesce(_max_upvotes, 3), -1);  -- -1 = upvoting off
  sub text := nullif(btrim(coalesce(_subtitle, '')), '');
  tmr int := greatest(coalesce(_timer_seconds, 0), 0);
  grp text := nullif(btrim(coalesce(_group_name, '')), '');
begin
  perform _require_admin(_pass);
  if btrim(coalesce(_title, '')) = '' then raise exception 'title required'; end if;
  if _type not in ('choice', 'words', 'open') then raise exception 'invalid type'; end if;
  if _type = 'choice' and jsonb_array_length(coalesce(_options, '[]')) < 2 then
    raise exception 'choice polls need at least 2 options';
  end if;
  if _id is null then
    insert into polls (title, subtitle, type, options, allow_multiple, max_upvotes, timer_seconds, group_name, position, session_id)
      values (btrim(_title), sub, _type, coalesce(_options, '[]'), coalesce(_allow_multiple, false), lim, tmr, grp,
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
    group_name = grp
    where id = _id;
  return _id;
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
    if coalesce(lim, 0) < 0 then
      raise exception 'upvoting is off for this poll';
    end if;
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

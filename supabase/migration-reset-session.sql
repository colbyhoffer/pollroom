-- ============================================================
-- Migration: reset every response in a session
-- For projects already running the previous schema/migrations.
-- Paste the whole file into the Supabase SQL Editor and Run.
-- ============================================================

create or replace function admin_reset_session(_pass text, _id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _require_admin(_pass);
  delete from votes where poll_id in (select id from polls where session_id = _id);
  delete from words where poll_id in (select id from polls where session_id = _id);
  delete from messages where session_id = _id;  -- poll responses + room chat; upvotes cascade
  update polls set revealed = false, timer_started_at = null where session_id = _id;
end $$;

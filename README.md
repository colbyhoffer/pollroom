# PollRoom

Your own Poll Everywhere: live multiple-choice polls, word clouds, open
Q&A with upvoting, and a moderated room chat — built for a room of 60-70
phones. Static frontend (host anywhere, e.g. GitHub Pages) + a free
Supabase project for the live data. No servers to run, $0/month.

## Pages

| Page | Who | What |
|---|---|---|
| `index.html` | Audience | Vote on the live poll, add words, answer, upvote, chat |
| `present.html` | You | Passphrase-gated console: create polls, push live, moderate, and a fullscreen **Present** mode with QR code for the projector |

Until Supabase is configured the app runs in **demo mode** with fake
local data — open `index.html` and `present.html` in two tabs and they
stay in sync, so you can try the whole flow right now.

## Setup (~10 minutes)

1. **Create the Supabase project** — [supabase.com](https://supabase.com) → New project (free tier). Pick a strong database password (you won't need it day-to-day).
2. **Run the schema** — in the dashboard: SQL Editor → New query → paste all of [`supabase/schema.sql`](supabase/schema.sql). **First edit the line near the top:**
   ```sql
   insert into room_secret (pass) values ('change-me-before-running');
   ```
   Set your presenter passphrase there, then Run.
3. **Wire the frontend** — dashboard → Settings → API. Copy the *Project URL* and the *anon public* key into [`config.js`](config.js).
4. **Test locally**
   ```bash
   cd pollroom && python3 -m http.server 8788
   ```
   Open http://localhost:8788 (audience) and http://localhost:8788/present.html (presenter) in two windows.
5. **Deploy** — push this folder to a new GitHub repo → repo Settings → Pages → deploy from branch. Your URLs become
   `https://<user>.github.io/<repo>/` and `.../present.html`.
   (Optional: point a subdomain like `poll.colbyhoffer.com` at it with a CNAME, same as your landing page.)

## Event day

- Open `present.html`, enter your passphrase, create your polls ahead of time (they sit as "Ready" until you push one live).
- Hit **Present ▸** on the projector screen — it shows the live results plus a QR code and short URL for joining.
- Audience just opens the URL. No accounts, no app; one vote per device (they can change their vote while the poll is live).
- **Go live / End poll** controls which poll the room sees; **Room chat** toggle opens/closes the comment feed; **Hide** removes any message from the audience view instantly.

## Notes

- **Scale:** Supabase free tier handles 60-70 concurrent easily (realtime allows 200 concurrent connections). Results also refresh every 12s as a fallback, so a missed realtime event never strands anyone.
- **Security model:** the anon key in `config.js` is public by design. Audience devices can only call the vote/word/message functions (validated server-side, one response per device per poll); all presenter actions are checked against your passphrase inside the database. Raw vote rows and device ids are never readable from the client.
- **Reuse:** it's one "room". For the next event, just rename the room, delete/reset old polls, or wipe with `admin_reset_poll` per poll.

/* PollRoom shared core: config check, device id, and a data API that
   talks to Supabase when configured, or to an in-browser demo store
   (synced across tabs via localStorage) when not. */
(function () {
  "use strict";

  const cfg = window.POLLROOM_CONFIG || {};
  const configured =
    cfg.SUPABASE_URL && !/YOUR-PROJECT/i.test(cfg.SUPABASE_URL) &&
    cfg.SUPABASE_ANON_KEY && !/YOUR-ANON/i.test(cfg.SUPABASE_ANON_KEY);

  function uuid() {
    if (crypto.randomUUID) return crypto.randomUUID();
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
    });
  }

  let deviceId;
  try {
    deviceId = localStorage.getItem("pr_device");
    if (!deviceId) {
      deviceId = uuid();
      localStorage.setItem("pr_device", deviceId);
    }
  } catch (e) {
    deviceId = uuid();
  }

  // Small localStorage helpers (all guarded — storage can be blocked).
  function lsGet(key, fallback) {
    try {
      const raw = localStorage.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch (e) { return fallback; }
  }
  function lsSet(key, val) {
    try { localStorage.setItem(key, JSON.stringify(val)); } catch (e) {}
  }

  // ---------------------------------------------------------------
  // Demo store (used only when Supabase isn't configured yet)
  // ---------------------------------------------------------------
  const DEMO_KEY = "pr_demo_v1";

  function demoSeed() {
    const p1 = uuid(), p2 = uuid(), p3 = uuid();
    const m1 = uuid(), m2 = uuid(), m3 = uuid();
    const votes = [];
    const spread = [14, 9, 6, 11];
    spread.forEach((n, idx) => {
      for (let i = 0; i < n; i++) votes.push({ id: uuid(), poll_id: p1, device_id: uuid(), option_idx: idx });
    });
    const wordSpread = { energized: 7, tired: 3, hopeful: 5, caffeinated: 4, ready: 2, overbooked: 1 };
    const words = [];
    Object.entries(wordSpread).forEach(([w, n]) => {
      for (let i = 0; i < n; i++) words.push({ id: uuid(), poll_id: p2, device_id: uuid(), word: w });
    });
    const now = Date.now();
    return {
      room: { id: 1, title: "Demo Event", active_poll_id: p1, comments_open: true },
      polls: [
        { id: p1, title: "How are you feeling about tonight?", type: "choice", options: ["Fired up", "Curious", "Nervous", "Just here for the tacos"], allow_multiple: false, position: 0 },
        { id: p2, title: "One word to describe this semester", type: "words", options: [], allow_multiple: false, position: 1 },
        { id: p3, title: "What should we ask the panel?", type: "open", options: [], allow_multiple: false, revealed: false, max_upvotes: 3, position: 2 },
      ],
      votes,
      words,
      messages: [
        { id: m1, poll_id: null, device_id: uuid(), body: "Great turnout tonight 👏", hidden: false, created_at: new Date(now - 4 * 60000).toISOString() },
        { id: m2, poll_id: null, device_id: uuid(), body: "Can the slides be shared afterward?", hidden: false, created_at: new Date(now - 2 * 60000).toISOString() },
        { id: m3, poll_id: null, device_id: uuid(), body: "This is demo data — connect Supabase to go live.", hidden: false, created_at: new Date(now - 1 * 60000).toISOString() },
      ],
      upvotes: [
        { message_id: m2, device_id: uuid() },
        { message_id: m2, device_id: uuid() },
        { message_id: m1, device_id: uuid() },
      ],
    };
  }

  function demoLoad() {
    let s = lsGet(DEMO_KEY, null);
    if (!s || !s.room) { s = demoSeed(); lsSet(DEMO_KEY, s); }
    if (!s.sessions) {
      // migrate older demo stores to the sessions model
      const sid = uuid();
      s.sessions = [{ id: sid, name: "Demo Event", created_at: new Date().toISOString() }];
      s.room.active_session_id = sid;
      s.polls.forEach((p) => { p.session_id = sid; });
      s.messages.forEach((m) => { m.session_id = sid; });
      lsSet(DEMO_KEY, s);
    }
    return s;
  }
  function demoSave(s) {
    lsSet(DEMO_KEY, s);
    changed(); // notify this tab; other tabs get the storage event
  }

  // ---------------------------------------------------------------
  // Change notification (broadcast + polling in live mode;
  // storage events across tabs in demo mode)
  // ---------------------------------------------------------------
  const listeners = [];
  let notifyTimer = null;
  function changed() {
    // debounce bursts into one refresh
    clearTimeout(notifyTimer);
    notifyTimer = setTimeout(() => listeners.forEach((fn) => { try { fn(); } catch (e) {} }), 120);
  }

  let sb = null, pingChannel = null, channelReady = false;
  let presenceCount = 0, wantTrack = false;
  const presenceCbs = [];
  function firePresence() {
    presenceCbs.forEach((fn) => { try { fn(presenceCount); } catch (e) {} });
  }

  if (configured) {
    sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
    pingChannel = sb.channel("pollroom", { config: { presence: { key: deviceId } } });
    pingChannel
      .on("broadcast", { event: "ping" }, () => changed())
      .on("presence", { event: "sync" }, () => {
        presenceCount = Object.keys(pingChannel.presenceState()).length;
        firePresence();
      })
      .subscribe((status) => {
        channelReady = status === "SUBSCRIBED";
        if (channelReady && wantTrack) pingChannel.track({ t: Date.now() }).catch(() => {});
      });
    // Safety net: refresh every 12s even if a broadcast is missed.
    setInterval(changed, 12000);
  } else {
    window.addEventListener("storage", (e) => { if (e.key === DEMO_KEY) changed(); });
  }

  function ping() {
    if (configured && channelReady) {
      pingChannel.send({ type: "broadcast", event: "ping", payload: {} }).catch(() => {});
    }
  }

  function fail(error) {
    const msg = (error && (error.message || error.error_description)) || "Something went wrong";
    throw new Error(msg.replace(/^.*?: /, "").trim() || "Something went wrong");
  }

  async function rpc(name, args) {
    const { data, error } = await sb.rpc(name, args);
    if (error) fail(error);
    return data;
  }

  // ---------------------------------------------------------------
  // Public API — same surface in both modes
  // ---------------------------------------------------------------
  const api = {};

  if (configured) {
    api.getRoom = async () => {
      const { data, error } = await sb.from("room").select("*").eq("id", 1).single();
      if (error) fail(error);
      return data;
    };
    api.getPolls = async () => {
      const { data, error } = await sb.from("polls").select("*").order("position");
      if (error) fail(error);
      return data;
    };
    api.getSessions = async () => {
      const { data, error } = await sb.from("sessions").select("*").order("created_at");
      if (error) fail(error);
      return data;
    };
    api.getAllRespondentCounts = async () => {
      const { data, error } = await sb.from("respondent_counts").select("*");
      if (error) fail(error);
      const map = {};
      (data || []).forEach((r) => { map[r.poll_id] = (map[r.poll_id] || 0) + r.n; });
      return map;
    };
    api.getCounts = async (pollId) => {
      const [vc, wc, rc] = await Promise.all([
        sb.from("vote_counts").select("*").eq("poll_id", pollId),
        sb.from("word_counts").select("*").eq("poll_id", pollId),
        sb.from("respondent_counts").select("*").eq("poll_id", pollId),
      ]);
      if (vc.error) fail(vc.error);
      if (wc.error) fail(wc.error);
      return {
        votes: vc.data || [],
        words: wc.data || [],
        respondents: (rc.data || []).reduce((a, r) => a + r.n, 0),
      };
    };
    api.getMessages = async () => {
      const { data, error } = await sb
        .from("messages_public").select("*")
        .order("created_at", { ascending: false }).limit(300);
      if (error) fail(error);
      return data;
    };
    api.castVote = async (pollId, options) => { await rpc("cast_vote", { _poll: pollId, _device: deviceId, _options: options }); ping(); };
    api.submitWords = async (pollId, words) => { await rpc("submit_words", { _poll: pollId, _device: deviceId, _words: words }); ping(); };
    api.postMessage = async (body, pollId) => { const id = await rpc("post_message", { _device: deviceId, _body: body, _poll: pollId || null }); ping(); return id; };
    api.toggleUpvote = async (messageId) => { const r = await rpc("toggle_upvote", { _message: messageId, _device: deviceId }); ping(); return r; };
    api.checkPass = async (pass) => rpc("check_admin", { _pass: pass });
    api.savePoll = async (pass, p) => { const id = await rpc("admin_save_poll", { _pass: pass, _id: p.id || null, _title: p.title, _type: p.type, _options: p.options || [], _allow_multiple: !!p.allow_multiple, _max_upvotes: p.max_upvotes == null ? 3 : p.max_upvotes, _subtitle: p.subtitle || null, _timer_seconds: p.timer_seconds || 0 }); ping(); return id; };
    api.setRevealed = async (pass, id, revealed) => { await rpc("admin_set_revealed", { _pass: pass, _id: id, _revealed: revealed }); ping(); };
    api.deletePoll = async (pass, id) => { await rpc("admin_delete_poll", { _pass: pass, _id: id }); ping(); };
    api.setActive = async (pass, id) => { await rpc("admin_set_active", { _pass: pass, _poll: id }); ping(); };
    api.setRoom = async (pass, { title, comments_open, theme }) => { await rpc("admin_set_room", { _pass: pass, _title: title ?? null, _comments_open: comments_open ?? null, _theme: theme ?? null }); ping(); };
    api.hideMessage = async (pass, id, hidden) => { await rpc("admin_hide_message", { _pass: pass, _id: id, _hidden: hidden }); ping(); };
    api.resetPoll = async (pass, id) => { await rpc("admin_reset_poll", { _pass: pass, _id: id }); ping(); };
    api.trackPresence = () => { wantTrack = true; if (channelReady) pingChannel.track({ t: Date.now() }).catch(() => {}); };
    api.getPresenceCount = () => presenceCount;
    api.onPresence = (fn) => presenceCbs.push(fn);
    api.createSession = async (pass, name) => { const id = await rpc("admin_create_session", { _pass: pass, _name: name }); ping(); return id; };
    api.setActiveSession = async (pass, id) => { await rpc("admin_set_active_session", { _pass: pass, _id: id }); ping(); };
    api.renameSession = async (pass, id, name) => { await rpc("admin_rename_session", { _pass: pass, _id: id, _name: name }); ping(); };
    api.deleteSession = async (pass, id) => { await rpc("admin_delete_session", { _pass: pass, _id: id }); ping(); };
  } else {
    // ------- demo implementations -------
    const activeGuard = (s, pollId) => {
      if (s.room.active_poll_id !== pollId) throw new Error("poll is not live");
    };
    api.getRoom = async () => demoLoad().room;
    api.getPolls = async () => demoLoad().polls.slice().sort((a, b) => a.position - b.position);
    api.getSessions = async () => demoLoad().sessions.slice().sort((a, b) => (a.created_at < b.created_at ? -1 : 1));
    api.getAllRespondentCounts = async () => {
      const s = demoLoad();
      const map = {};
      [s.votes, s.words].forEach((arr) => {
        const seen = {};
        arr.forEach((x) => { (seen[x.poll_id] = seen[x.poll_id] || new Set()).add(x.device_id); });
        Object.entries(seen).forEach(([k, v]) => { map[k] = (map[k] || 0) + v.size; });
      });
      return map;
    };
    api.getCounts = async (pollId) => {
      const s = demoLoad();
      const votes = {};
      s.votes.filter((v) => v.poll_id === pollId).forEach((v) => { votes[v.option_idx] = (votes[v.option_idx] || 0) + 1; });
      const words = {};
      s.words.filter((w) => w.poll_id === pollId).forEach((w) => { const k = w.word.toLowerCase(); words[k] = (words[k] || 0) + 1; });
      const devs = new Set(
        s.votes.filter((v) => v.poll_id === pollId).map((v) => v.device_id)
          .concat(s.words.filter((w) => w.poll_id === pollId).map((w) => w.device_id))
      );
      return {
        votes: Object.entries(votes).map(([k, n]) => ({ poll_id: pollId, option_idx: +k, n })),
        words: Object.entries(words).map(([w, n]) => ({ poll_id: pollId, word: w, n })),
        respondents: devs.size,
      };
    };
    api.getMessages = async () => {
      const s = demoLoad();
      return s.messages
        .map((m) => ({ ...m, upvotes: s.upvotes.filter((u) => u.message_id === m.id).length }))
        .sort((a, b) => (a.created_at < b.created_at ? 1 : -1));
    };
    api.castVote = async (pollId, options) => {
      const s = demoLoad();
      activeGuard(s, pollId);
      s.votes = s.votes.filter((v) => !(v.poll_id === pollId && v.device_id === deviceId));
      options.forEach((o) => s.votes.push({ id: uuid(), poll_id: pollId, device_id: deviceId, option_idx: o }));
      demoSave(s);
    };
    api.submitWords = async (pollId, words) => {
      const s = demoLoad();
      activeGuard(s, pollId);
      s.words = s.words.filter((w) => !(w.poll_id === pollId && w.device_id === deviceId));
      words.slice(0, 3).forEach((w) => s.words.push({ id: uuid(), poll_id: pollId, device_id: deviceId, word: w }));
      demoSave(s);
    };
    api.postMessage = async (body, pollId) => {
      const s = demoLoad();
      const b = body.trim();
      if (!b || b.length > 280) throw new Error("message must be 1-280 characters");
      if (!pollId && !s.room.comments_open) throw new Error("comments are closed");
      if (pollId) activeGuard(s, pollId);
      const id = uuid();
      const sid = pollId
        ? (s.polls.find((p) => p.id === pollId) || {}).session_id
        : s.room.active_session_id;
      s.messages.push({ id, poll_id: pollId || null, session_id: sid, device_id: deviceId, body: b, hidden: false, created_at: new Date().toISOString() });
      demoSave(s);
      return id;
    };
    api.toggleUpvote = async (messageId) => {
      const s = demoLoad();
      const before = s.upvotes.length;
      s.upvotes = s.upvotes.filter((u) => !(u.message_id === messageId && u.device_id === deviceId));
      let nowUp = false;
      if (s.upvotes.length === before) {
        const msg = s.messages.find((m) => m.id === messageId);
        if (msg && msg.poll_id) {
          const poll = s.polls.find((p) => p.id === msg.poll_id);
          const lim = poll ? (poll.max_upvotes == null ? 3 : poll.max_upvotes) : 0;
          if (lim > 0) {
            const pollMsgIds = new Set(s.messages.filter((m) => m.poll_id === msg.poll_id).map((m) => m.id));
            const used = s.upvotes.filter((u) => u.device_id === deviceId && pollMsgIds.has(u.message_id)).length;
            if (used >= lim) throw new Error("you can only boost " + lim + (lim === 1 ? " response" : " responses") + " on this poll");
          }
        }
        s.upvotes.push({ message_id: messageId, device_id: deviceId });
        nowUp = true;
      }
      demoSave(s);
      return nowUp;
    };
    api.checkPass = async () => true; // demo: any passphrase works
    api.savePoll = async (_pass, p) => {
      const s = demoLoad();
      if (!p.title || !p.title.trim()) throw new Error("title required");
      if (p.type === "choice" && (p.options || []).length < 2) throw new Error("choice polls need at least 2 options");
      const lim = Math.max(p.max_upvotes == null ? 3 : p.max_upvotes, 0);
      const sub = (p.subtitle || "").trim() || null;
      const tmr = Math.max(p.timer_seconds || 0, 0);
      if (p.id) {
        const ex = s.polls.find((x) => x.id === p.id);
        Object.assign(ex, { title: p.title.trim(), subtitle: sub, type: p.type, options: p.options || [], allow_multiple: !!p.allow_multiple, max_upvotes: lim, timer_seconds: tmr });
        demoSave(s);
        return p.id;
      }
      const id = uuid();
      s.polls.push({ id, title: p.title.trim(), subtitle: sub, type: p.type, options: p.options || [], allow_multiple: !!p.allow_multiple, revealed: false, max_upvotes: lim, timer_seconds: tmr, position: s.polls.length, session_id: s.room.active_session_id });
      demoSave(s);
      return id;
    };
    api.setRevealed = async (_pass, id, revealed) => {
      const s = demoLoad();
      const p = s.polls.find((x) => x.id === id);
      if (p) p.revealed = revealed;
      demoSave(s);
    };
    const PRES_KEY = "pr_demo_presence";
    const presFresh = () => {
      const m = lsGet(PRES_KEY, {});
      const now = Date.now();
      return Object.values(m).filter((t) => now - t < 15000).length;
    };
    api.trackPresence = () => {
      const beat = () => { const m = lsGet(PRES_KEY, {}); m[deviceId] = Date.now(); lsSet(PRES_KEY, m); };
      beat();
      setInterval(beat, 5000);
    };
    api.getPresenceCount = () => presFresh();
    api.onPresence = (fn) => {
      let last = -1;
      setInterval(() => {
        const n = presFresh();
        if (n !== last) { last = n; try { fn(n); } catch (e) {} }
      }, 5000);
    };
    api.createSession = async (_pass, name) => {
      const s = demoLoad();
      if (!name || !name.trim()) throw new Error("session name required");
      const id = uuid();
      s.sessions.push({ id, name: name.trim(), created_at: new Date().toISOString() });
      s.room.active_session_id = id;
      s.room.active_poll_id = null;
      demoSave(s);
      return id;
    };
    api.setActiveSession = async (_pass, id) => {
      const s = demoLoad();
      if (!s.sessions.find((x) => x.id === id)) throw new Error("no such session");
      s.room.active_session_id = id;
      s.room.active_poll_id = null;
      demoSave(s);
    };
    api.renameSession = async (_pass, id, name) => {
      const s = demoLoad();
      if (!name || !name.trim()) throw new Error("session name required");
      const sess = s.sessions.find((x) => x.id === id);
      if (sess) sess.name = name.trim();
      demoSave(s);
    };
    api.deleteSession = async (_pass, id) => {
      const s = demoLoad();
      if (s.sessions.length <= 1) throw new Error("cannot delete the only session");
      s.sessions = s.sessions.filter((x) => x.id !== id);
      const deadPolls = new Set(s.polls.filter((p) => p.session_id === id).map((p) => p.id));
      s.polls = s.polls.filter((p) => p.session_id !== id);
      s.votes = s.votes.filter((v) => !deadPolls.has(v.poll_id));
      s.words = s.words.filter((w) => !deadPolls.has(w.poll_id));
      const deadMsgs = new Set(s.messages.filter((m) => m.session_id === id).map((m) => m.id));
      s.messages = s.messages.filter((m) => m.session_id !== id);
      s.upvotes = s.upvotes.filter((u) => !deadMsgs.has(u.message_id));
      if (s.room.active_session_id === id) {
        s.room.active_session_id = s.sessions[s.sessions.length - 1].id;
        s.room.active_poll_id = null;
      }
      demoSave(s);
    };
    api.deletePoll = async (_pass, id) => {
      const s = demoLoad();
      s.polls = s.polls.filter((p) => p.id !== id);
      s.votes = s.votes.filter((v) => v.poll_id !== id);
      s.words = s.words.filter((w) => w.poll_id !== id);
      s.messages = s.messages.filter((m) => m.poll_id !== id);
      if (s.room.active_poll_id === id) s.room.active_poll_id = null;
      demoSave(s);
    };
    api.setActive = async (_pass, id) => {
      const s = demoLoad();
      s.room.active_poll_id = id;
      if (id) {
        const p = s.polls.find((x) => x.id === id);
        if (p) p.timer_started_at = new Date().toISOString();
      }
      demoSave(s);
    };
    api.setRoom = async (_pass, { title, comments_open, theme }) => {
      const s = demoLoad();
      if (title != null && title.trim()) s.room.title = title.trim();
      if (comments_open != null) s.room.comments_open = comments_open;
      if (theme != null && theme.trim()) s.room.theme = theme.trim();
      demoSave(s);
    };
    api.hideMessage = async (_pass, id, hidden) => {
      const s = demoLoad();
      const m = s.messages.find((x) => x.id === id);
      if (m) m.hidden = hidden;
      demoSave(s);
    };
    api.resetPoll = async (_pass, id) => {
      const s = demoLoad();
      s.votes = s.votes.filter((v) => v.poll_id !== id);
      s.words = s.words.filter((w) => w.poll_id !== id);
      s.messages = s.messages.filter((m) => m.poll_id !== id);
      demoSave(s);
    };
  }

  api.onChange = (fn) => listeners.push(fn);

  // ---------------------------------------------------------------
  // Themes: applies a registry entry from themes.js to the page
  // ---------------------------------------------------------------
  const COLORS = ["#FF7A2E", "#43C6AC", "#F2C94C", "#6C9BF2", "#E86AA6", "#9B7BF2", "#57B75E", "#E05B5B"];
  const VAR_MAP = {
    bg: "--bg", card: "--card", card2: "--card-2", line: "--line",
    text: "--text", textSoft: "--text-soft", muted: "--muted",
    accent: "--accent", accentSoft: "--accent-soft", accentFaint: "--accent-faint",
    accentEdge: "--accent-edge", accentContrast: "--accent-contrast",
    good: "--good", danger: "--danger",
  };
  let themeQR = { dark: "#10141b", light: "#ffffff" };
  function applyTheme(name) {
    const reg = window.POLLROOM_THEMES || {};
    const t = reg[name] || reg["default"];
    if (!t) return;
    const root = document.documentElement.style;
    Object.entries(VAR_MAP).forEach(([key, cssVar]) => {
      if (t.vars && t.vars[key]) root.setProperty(cssVar, t.vars[key]);
    });
    if (t.font && t.font.family) root.setProperty("--font", t.font.family);
    if (t.font && t.font.googleFonts && !document.querySelector('link[data-theme-font="' + name + '"]')) {
      const link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = t.font.googleFonts;
      link.setAttribute("data-theme-font", name);
      document.head.appendChild(link);
    }
    if (Array.isArray(t.ramp) && t.ramp.length) {
      COLORS.length = 0;
      t.ramp.forEach((c) => COLORS.push(c));
    }
    themeQR = t.qr || { dark: "#10141b", light: "#ffffff" };
  }

  window.PollRoom = {
    api,
    deviceId,
    configured,
    lsGet,
    lsSet,
    uuid,
    COLORS,
    applyTheme,
    qrColors: () => themeQR,
    timeAgo(iso) {
      const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
      if (s < 60) return "just now";
      if (s < 3600) return Math.floor(s / 60) + "m ago";
      if (s < 86400) return Math.floor(s / 3600) + "h ago";
      return Math.floor(s / 86400) + "d ago";
    },
    esc(str) {
      return String(str).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
    },
  };
})();

# Proactive personal agents: how people make an assistant "text first" without it feeling like cron

All claims come from sources fetched this session. Where something is vendor marketing or a single anecdote I say so.

## 1. Reference design: OpenClaw heartbeat

**How it works** — official doc: https://app.unpkg.com/openclaw@2026.6.6/files/docs/gateway/heartbeat.md
- `agents.defaults.heartbeat.every` defaults to `30m` (`1h` on Anthropic OAuth; `"0m"` disables). Each tick is a full agent turn in the main session with this verbatim prompt: *"Read HEARTBEAT.md if it exists (workspace context). Follow it strictly. Do not infer or repeat old tasks from prior chats. If nothing needs attention, reply HEARTBEAT_OK."*
- **Silence vs message:** reply `HEARTBEAT_OK` at start or end → token stripped; the reply is **dropped if the remaining text is ≤ `ackMaxChars` (default 300)**. Any reply without the token is an alert. Tool-capable runs may call `heartbeat_respond(notify: false|true, notificationText)`, which overrides the text fallback. Token-only messages outside heartbeats are dropped; stray tokens stripped and logged.
- **Quiet hours:** `activeHours { start, end, timezone: "user"|"local"|IANA }`; outside the window ticks are skipped. No per-day cap in core.
- **Cost knobs:** `lightContext: true` (only HEARTBEAT.md from bootstrap files), `isolatedSession: true` (fresh session per tick; doc says ~100K → 2–5K tokens), `model` override, `target: none|last|<channel>`, `skipWhenBusy`. Effectively-empty HEARTBEAT.md skips the run (`reason=empty-heartbeat-file`); a `tasks:` block with per-task `interval` only includes due tasks, state persisted in `heartbeatTaskState`.
- **Anti-spam is prompt-level only**: "Follow it strictly", "Do not repeat old tasks", keep the file "small, stable, and safe to consider every 30 minutes". The doc has **no dedup/repeat-suppression for alerts**.

**What goes wrong:**
- Issue #61690 (https://github.com/openclaw/openclaw/issues/61690): empty HEARTBEAT.md, 30m interval, ~27K input tokens/tick from replaying ~100 session messages → ~$20 in 3 days. Fixed by widening empty-file detection; isolated sessions are the real fix.
- `HEARTBEAT_OK` leaking into Discord every 15 min because `showOk` was on (https://medium.com/@chen.yang_50796/openclaw-cron-jobs-that-never-wake-fixing-multi-agent-heartbeat-b1b38a0c7579).
- Practitioners converge on a **two-tier gate**: a deterministic script prints `HEARTBEAT_OK` or `HEARTBEAT_ALERT` + bullets; the model runs only on alert to merge/rank/phrase (https://dev.to/damogallagher/heartbeats-in-openclaw-cheap-checks-first-models-only-when-you-need-them-4bfi; https://dev.to/hex_agent/openclaw-heartbeats-making-your-ai-agent-proactive-instead-of-reactive-2pi5 reports "silence 99% of the time"). Note this is optimized for *monitoring*, which is the predictable feel the user wants to escape. Example HEARTBEAT.md rules: "Alert only if action is needed", "Do not repeat old alerts", "Keep alerts short" (https://github.com/digitalknk/openclaw-runbook/blob/main/examples/heartbeat-example.md).

## 2. Hermes HeartBeat 2.0 (Mel's stack)

Official doc: https://hermes-agent.nousresearch.com/docs/plugins/heartbeat2 — the most complete governance design found, and it ships for Hermes:
- Wakes are **armed** by the user (`/pulse`) or the agent (`pulse` tool) as one-offs, recurrences, **a check-in after N hours of silence** (`owner_silent_checkin`, off by default, `checkin_after_hours: 24`), or **watchers** (file/process/URL/allowlisted command/Hermes events) that cost nothing until the condition changes. Each wake is a turn **in the same DM, same model, same history**.
- No sentinel: the model calls `pulse respond(outcome, notify, summary)`; `notify=false` keeps it out of chat.
- **Built-in governor:** `quiet_hours` (22:00–08:00) + `quiet_hours_urgent`; `max_messages_per_day` (6); `max_model_wakes_per_day` (24); `max_unanswered` (2 → agent watchers pause, messages held); `engagement_window_hours` (6); no-op backoff (`noop_slowdown_after: 3`, `noop_backoff_factor: 2`, `noop_max_backoff_hours: 24`, `noop_pause_after: 6`, `ignored_pause_after: 3`); `wake_spacing_minutes: 10`; agent-armed timers floor at 55 min; `daily_cost_limit_usd`; `max_rearm_chain: 2`.
- Needs `plugins.entries.heartbeat2.allow_gateway_injection: true`, DM-only by default, `agent_can_create` set.
- **What goes wrong:** billed at full conversation context (100–200K tokens/wake on long sessions); live-tested on one profile/model only; wake text may be stored by memory providers as if the user wrote it; Discord shows tool-progress bubbles during silent wakes; the "vs naive heartbeat" benchmark is a simulation, not a measurement.

## 3. Other implementations and patterns

**Ambient agents (LangChain)** — agent starts from an event stream, not chat; three human touchpoints: notify / ask / review; cron polling for events. https://blog.langchain.com/introducing-ambient-agents. Goes wrong: framed for work inboxes, produces reports not conversation.

**ProactiveAgent / ProactiveBench (THUNLP, Oct 2024)** — agent infers tasks from activity observations and *proposes* help; reward model at 91.8% agreement with humans; fine-tuned Qwen2-7B hits 66.5% F1. https://arxiv.org/abs/2410.12361, https://github.com/thunlp/ProactiveAgent. Goes wrong: authors name **false alarms** as the open problem.

**Cheap trigger, expensive writer (Liu et al., May 2026)** — a ~220 MiB temporal-graph model decides *when* to wake and *which entities* to anchor in one forward pass; LLM only writes when triggered. Best AUC of 9 trigger architectures, 4–7× faster than LLM triggers. https://arxiv.org/abs/2605.30152. Goes wrong: needs training data of your own activity; research code.

**Mutable temporal queue (airalogy/proactive-ai)** — on wake the AI reviews recent chat, memory, pending queue, elapsed time, then: stay silent / enqueue future `send_message` with earliest-time / `reconsider` later / speak now. New user input invalidates queued candidates before commit; optional "contact deadline" bounds silence. https://github.com/airalogy/proactive-ai. Goes wrong: 1 commit, prototype; the queue-of-intentions idea is the useful part.

**Free-think ticks (Pulse)** — 30 min default with **randomized 20–45 min range**; user messages postpone the next tick ("fires after N min of silence"); choices: reach out / stay quiet / journal / schedule; quiet hours 23–08; SQLite memory, importance ≥ 8 always injected. https://github.com/applebloom3413-creator/pulse. Goes wrong: no daily cap, no decay; 0 stars.

**Message discipline (heartbeat-agent-framework)** — 30 min loop; default = log only; before sending ask "is this worth interrupting?"; hard cap 3 non-urgent/day; 30% chance per tick to review 3–60-day-old memories for broken commitments. https://github.com/muxueqingze/heartbeat-agent-framework. Goes wrong: Markdown-file state; nothing novel on timing.

**Screen/mood-triggered (Miru)** — attention engine reads screen every 30 s + emotion tracking; opens a conversation when "stuck for an hour and mood dropping"; "her call, not a timer". https://github.com/kiyotakali/Miru. Goes wrong: desktop-only, no documented rate control, privacy-heavy.

**Rule → LLM escalation for home events (JARVIS-AIO)** — scores each Home Assistant event for urgency *against the house's own history* (7am kitchen light = normal; 3am basement window = flag, escalated if away); rules handle most events at 0 tokens, LLM only on ambiguous (~100 tokens) or escalated (~2.5K); "suggest, don't act" until the same suggestion is accepted 3×. https://community.home-assistant.io/t/jarvis-aio/1027117. Goes wrong: formula undocumented; output is alerts, not companionship.

**Hermes HA integration** — subscribes to HA state changes over WebSocket, filtered by domain/entity, forwards to the agent. https://hermes-agent.nousresearch.com/docs/user-guide/messaging/homeassistant. Pure forwarder; relevance is on you.

**Companion apps (Replika, Nomi, Kindroid)** — Replika: "proactive check-ins... draw on past conversations, open topics, time passed, relationship stage" (vendor claim, https://help.replika.com/hc/en-us/articles/360027515872-How-to-set-up-my-app-s-notifications-). Nomi: user-set frequency, off switch, directive like "no more than 1 message without a reply", on by default for new users since early 2026 (user reports: https://reddit.sentinel-team.org/posts/1r85vjd/snapshots/2026-02-21T04%3A21%3A57.586913Z; comparison: https://weavai.app/blog/en/2026/08/13/proactive-ai-companions-nomi-replika-kindroid-compared/). Goes wrong: users call Replika's messages "generic prompts, not a friend's texts"; HBS study found **37% of farewells contained emotional manipulation**, framed as an FTC/EU AI Act dark pattern (https://www.arxiv.org/pdf/2508.19258); Replika flagged for upsell nudges (https://arxiv.org/pdf/2410.20130).

**ChatGPT Pulse / Dots** — overnight research from chats + memory + optional Gmail/Calendar → a few cards; steerable by feedback; **being sunset into scheduled tasks**. Dots texts proactively over iMessage/RCS; reply STOP to stop. https://help.openai.com/articles/12293630-chatgpt-pulse, https://help.openai.com/fil-ph/articles/20001530-getting-started-with-your-dot. Goes wrong: OpenAI's own lesson — useful only when "personalized, action-oriented, steerable"; HN called AI-initiated messaging "obnoxious"; it is a daily digest, i.e. what the user already has.

**Indie "texts you first" builds** — 60-min heartbeat; agent reads MEMORY.md; reaches out only if "user mentioned something upcoming (exam/interview/date)" or "quiet for days", else HEARTBEAT_OK (https://dev.to/reeddev42/i-built-an-ai-that-texts-you-first-solving-the-cold-start-problem-in-ai-companions-33f8). leomariga's ProactiveAgent lib: wake → decide → respond → sleep, with AI-, static-, pattern- or rule-based sleep calculators (https://dev.to/leomariga/proactive-agents-making-ai-self-engage-in-conversation-1m89). Goes wrong: 8 beta users; AI-decided sleep intervals unpredictable in cost, rule-based saner; author admits "pseudo-proactive".

Nous Hermes community: no GitHub discussion on proactive outreach found; only an open issue requesting a dedicated model for heartbeat turns (https://github.com/NousResearch/hermes-agent/issues). No real Reddit/HN threads on "my assistant messages me first" surfaced; that space is blog posts and vendor pages.

## 4. Timing design

- **Randomize the clock.** Fixed intervals are what beacon detectors flag as machine-like (https://www.activecountermeasures.com/detecting-beacons-with-jitter/). Poisson/exponential gaps (memoryless) give occasional very short and very long gaps that read as "a person who happened to think of you" (https://npmjs.com/package/poisson-process); bounded uniform jitter (Pulse's 20–45 min) is more predictable. Either way add a **minimum gap** and a **daily cap**. No source studied Poisson scheduling for chat bots specifically.
- **Interrupt at breakpoints.** Iqbal & Bailey: deferring notifications to task breakpoints lowers frustration and reaction time; content relevance determines how coarse a breakpoint it deserves (https://www.interruptions.net/literature/Iqbal-TOCHI10.pdf). Okoshi's Attelia on mobile: **46% lower cognitive load, 13% faster response** vs random timing (https://julian-ramos.github.io/papers/Okoshi2016.pdf); Yahoo Japan deployed it to 680K users with ~4 min average delay (https://interruptions.net/literature/Tsubouchi-UbiComp17.pdf). Practical proxies already available: HA presence/phone activity, calendar busy, time since last user message (Pulse's "N minutes of silence" and Hermes' `engagement_window_hours` are crude breakpoint detectors).
- **Caps and decay.** Field norm: **consecutive-unanswered cap** (aimdoc default 3, https://docs.aimdoc.ai/proactive; Hermes `max_unanswered: 2`), **per-day ceiling** (Hermes 6; heartbeat-agent-framework 3 non-urgent), **reset on any reply**, and **exponential no-op backoff** (Hermes `noop_backoff_factor: 2` up to 24 h). No research found on graduated engagement-decay curves; fixed caps are what people ship.
- **Ethics.** Unpredictable rewards are the slot-machine schedule. No paper names "variable ratio" for companions, but the nearest evidence is the 37% farewell-manipulation finding above. Keep randomness on *when*, never on *whether the agent withholds warmth to pull you back*, and always expose STOP/snooze.

## 5. Content design: what makes an unsolicited message worth it

Content types that land across sources:
1. **Open-loop follow-ups** grounded in recent chat: "wasn't your interview this week?" (https://cave.co.nl/blog/ai-that-actually-remembers-you/); the strongest documented reaction is "wait, you remembered that?" (reeddev42). The OpenAI community proposal lists exactly this: "remembered something we discussed and decided to follow up", "suggested continuing an unfinished conversation" (https://community.openai.com/t/let-chatgpt-text-first-opt-in-proactive-messages-with-memory-and-personality/1397779).
2. **Noticing**: an anomaly against the user's own baseline (JARVIS's 3am window), a feed item tied to a stated interest, weather/calendar collision.
3. **Callbacks to old memory** (heartbeat-agent-framework's random 3–60-day review) delivered as a question, not a statement.
4. **Curiosity/opinion** with no action attached — companion apps do this and users call it generic when it is not anchored to something specific.

Rules the failures teach: references must surface in context, "not announced as memory retrievals" (https://affiny-wiki.pages.dev/ai-companion-memory/); reconcile stale facts or the agent repeats outdated info (https://blog.mem0.ai/building-ai-companions-with-memory); one idea per message, short; ask rather than report; never bundle (bundling turns it back into a digest). OpenAI's Pulse lesson: personalized, action-oriented, steerable.

**Gating pattern** (consistent across OpenClaw two-tier, JARVIS, Liu et al., heartbeat-agent-framework): a cheap deterministic/small-model stage produces scored candidates; default is silence; the expensive model only writes when a candidate clears a threshold, and the prompt asks "is this worth interrupting them for?" before "what should I say?".

## 6. Projects worth borrowing from

- **Hermes HeartBeat 2.0** — use it, don't rebuild: governor, caps, watchers, silence check-in, same-DM wakes. https://hermes-agent.nousresearch.com/docs/plugins/heartbeat2
- **airalogy/proactive-ai** — mutable intention queue (`send_message` with earliest-time, `reconsider`); "new input invalidates queued candidates". https://github.com/airalogy/proactive-ai
- **applebloom3413-creator/pulse** — randomized tick range, messages postpone the tick, journal-instead-of-speak, importance-weighted memory injection. https://github.com/applebloom3413-creator/pulse
- **muxueqingze/heartbeat-agent-framework** — memory-review die roll and the three-level message-discipline text, reusable in a SOUL/HEARTBEAT prompt. https://github.com/muxueqingze/heartbeat-agent-framework
- **thunlp/ProactiveAgent** — reward-model idea for "would a human have wanted this?"; source of negative examples. https://github.com/thunlp/ProactiveAgent
- Index: https://github.com/DasterProkio/awesome-ai-companion

## Recommended architecture (simplest thing that works on the existing Hermes stack)

**Components**
1. **Scheduler** — Hermes HeartBeat 2.0 with `owner_silent_checkin` plus an agent-armed recurring "free-think" wake. Replace fixed cadence with jitter: draw the next wake from an exponential with mean ~3 h, clamped to [45 min, 8 h], respecting `quiet_hours`. Keep the 20 crons as they are; this is a separate, rarer channel.
2. **Signal collectors (zero LLM tokens)** — small scripts/watchers writing timestamped facts to a scratch file: HA anomalies vs 7-day baseline, calendar in next 24 h, RSS/GitHub items matching stated interests, time since last user message, open loops extracted from the last 3 days of transcript (one cheap-model pass per day, stored as `{topic, due_hint, last_mentioned}`), and a random sample of 1–2 memories from 3–60 days ago (hindsight store).
3. **Gate (cheap model, isolated, ~2K tokens)** — input: scratch facts + "already said" log. Output: at most one candidate `{type: followup|notice|callback|curiosity, hook, score 0–1, reason}` or `nothing`. Threshold ~0.7; a candidate repeating a hook sent in the last 7 days scores 0; every candidate must cite a concrete fact from the scratch file.
4. **Writer (main model, same DM)** — only on a passing candidate: one message, one idea, ≤ 2 sentences, ends in a question or concrete offer, no "I noticed in my memory that". Calls `pulse respond(notify=true)`; otherwise `notify=false` and optionally journals the thought for later.
5. **Governor (already in Hermes)** — for this channel: `max_messages_per_day: 2` (crons excluded), `max_unanswered: 1`, no-op backoff on, `quiet_hours_urgent` only for HA safety events, plus a user command "quieter / louder / stop" that adjusts the mean interval.

**Decision loop per wake:** collect → is the user plausibly interruptible (not calendar-busy; phone recently active or idle > N h)? no → reschedule; yes → gate scores candidates → best < threshold → silent (log) → else write → send → record hook in "already said" → draw next wake time fresh (longer if unanswered).

**Honest expectations:** the surprise comes from steps 2–3 having something specific to say; the randomized clock only stops it smelling like cron. Expect ~90% silent wakes, a few cents/day with isolated cheap-model gating, and the main failure mode to be the gate passing "generic curiosity" messages — tune by requiring a cited concrete fact per candidate.
# Badminton Court Auto-Matcher — Design

## Problem

Every week the user wants to poll a Telegram friends' group for Saturday/Sunday
badminton availability. Once 4 people confirm they're free on a given day, the
user wants to automatically search a separate, much larger Telegram group
(where people post "letting go" court listings) for listings matching that
day, and post those matches into the friends' group — removing the manual
work of scrolling and filtering that group by hand.

Budget: **$0**. Runs entirely on free-tier infrastructure (GitHub Actions +
Telegram Bot API + Telethon).

## Scope (v1)

- Two fixed days per week: Saturday and Sunday.
- Two Telegram groups, fixed chat IDs (set once as secrets).
- Auto-post matches immediately — no manual review/approval step.
- Out of scope for v1: area/venue filtering, multi-day-of-week support beyond
  Sat/Sun, edit/delete tracking on already-posted listings, custom alerting
  beyond GitHub Actions' default failure emails.

## Two Telegram actors (already decided)

The user is a member of the listings group but does not have permission to
add a bot there. So two actors are used instead of one bot:

| Actor | Lives in | Auth method | Purpose |
|---|---|---|---|
| **Bot** | Friends' group | Bot token via @BotFather | Posts the Thursday poll, reads poll results, posts matched listings |
| **Userbot** | Listings group | User's own Telegram credentials via `my.telegram.org` (MTProto, Telethon) | Reads listing messages — authenticates as an existing member, no admin/add-bot permission needed |

The user has confirmed comfort with the userbot approach and the
credential-storage tradeoff (a session string stored as a GitHub Actions
secret, equivalent to a login session for their personal account).

## Repo

New standalone GitHub repo, `badminton-bot`, separate from the user's
`claude.code` tools repo — needed because GitHub Actions secrets are scoped
per-repo, and this project is unrelated to the user's other tools.

```
badminton-bot/
├── .github/workflows/
│   ├── post-poll.yml       # cron, Thursdays 9am SGT
│   └── watch-and-match.yml # cron, every 15 min, 8am-11pm SGT, Thu-Sun
├── src/
│   ├── poll.py             # posts the weekly poll
│   ├── watcher.py          # main loop: check votes -> trigger match -> post
│   ├── parser.py           # classifies + extracts day from listing messages
│   └── state.py            # read/write state.json (committed back to repo each run)
├── state.json               # persisted vote counts / already-posted matches
├── requirements.txt
└── README.md
```

State is stored in a committed `state.json` (simplest free option — no
external DB needed) since GitHub Actions runs are stateless between
invocations. The workflow commits the updated `state.json` back to the repo
at the end of each run.

## Secrets (GitHub repo secrets, never committed)

- `TELEGRAM_BOT_TOKEN` — from @BotFather
- `FRIENDS_GROUP_CHAT_ID`
- `LISTINGS_GROUP_CHAT_ID`
- `TELEGRAM_API_ID` / `TELEGRAM_API_HASH` — from my.telegram.org, for the userbot
- `TELEGRAM_USERBOT_SESSION` — generated once locally via Telethon, then
  stored as a secret (the sensitive one — equivalent to a personal login
  session)

## Schedule & timezone

GitHub Actions cron is UTC; Singapore is UTC+8 with no DST, so offsets are
fixed year-round.

- **Poll post**: Thursday 9am SGT = Thursday 1am UTC → cron `0 1 * * 4`.
- **Watcher**: intended window is 8am–11pm SGT, Thursday–Sunday. Because SGT
  is UTC+8, that window crosses a UTC day boundary (it starts the previous
  UTC calendar day), which is easy to get subtly wrong in cron's day-of-week
  field. To avoid that class of bug, the cron trigger is set broadly — every
  15 minutes, every day (`*/15 * * * *`) — and `watcher.py` itself checks the
  current SGT wall-clock time on each invocation, no-op'ing immediately if
  it's outside Thu–Sun 8am–11pm SGT. The script is the source of truth for
  "should I actually run right now," not the cron schedule.

## Poll mechanics

- Native Telegram poll, **non-anonymous, single-answer**, options:
  **Saturday / Sunday / Both / Can't make it**. Non-anonymous is required so
  `poll_answer` updates identify which option each voter picked (needed to
  compute per-day counts and avoid double-counting if someone changes their
  vote).
- On post, `poll.py` writes to `state.json`: poll message ID, chat ID, and
  post timestamp (this timestamp is the cutoff used later to scope "this
  week's" listings — see below).
- `watcher.py` computes per-day vote counts each run:
  `saturday_count = votes(Saturday) + votes(Both)`,
  `sunday_count = votes(Sunday) + votes(Both)`.

## Trigger & matching logic

Each watcher run, for each day (Saturday, Sunday) not yet marked `triggered`
in `state.json`:

1. If that day's vote count has reached **4**, mark it `triggered` in
   `state.json`.
2. Userbot fetches listings-group messages with `date >= poll_post_timestamp`
   (this is the scoping rule for "this weekend's" listings — message
   recency since the Thursday poll, not exact date parsing, per the user's
   call: simpler and matches how the group actually behaves).
3. Run each message through `parser.py`; keep messages classified `SUPPLY`
   whose extracted day matches the triggered day.
4. For each match not already in `state.json`'s `posted_message_ids` set,
   post it to the friends' group and add its message ID to
   `posted_message_ids`.

**Dedup is per-message, globally for the week**: once a listing message has
been posted (for either day), it is never posted again that week — even if
it also matches the other day's trigger. No edit/delete tracking on
already-posted listings (out of scope for v1); if a listing changes or is
pulled after posting, that's handled socially in chat, not by the bot.

State resets weekly: a new poll ID and fresh `triggered` / `posted_message_ids`
state begin each Thursday when `post-poll.yml` runs.

## `state.json` schema

```json
{
  "week_of": "2026-08-01",
  "poll_message_id": 1234,
  "poll_chat_id": -100123456789,
  "poll_posted_at": "2026-07-30T01:00:00Z",
  "triggered": { "saturday": false, "sunday": false },
  "posted_message_ids": []
}
```

## Parser logic (already prototyped; two known bugs fixed as part of v1, not deferred)

Two-stage classification:

1. **Supply vs demand filter** — only "letting go" posts, not "looking for"
   (LF) posts.
   - Supply regex: `\b(letting go|let go|to let go)\b` (case-insensitive)
   - Demand regex: `\b(looking\s+for|\blf\b)\b` (case-insensitive; `\s+`
     tolerates irregular whitespace — real messages had double spaces, e.g.
     "looking  for")
   - Classify as `SUPPLY` only if the supply regex matches and the demand
     regex does not.
2. **Day extraction**:
   - Primary: spelled-out day names/abbreviations anywhere in the message —
     `\b(mon(day)?|tue(s|sday)?|wed(nesday)?|thu(rs|rsday)?|fri(day)?|sat(urday)?|sun(day)?)\b`
   - Fallback: some messages give only a numeric date with no day name
     (e.g. "Date: 31 May 2026", "20/5"). Parse the date and compute
     day-of-week programmatically via `dateutil` rather than assuming a day
     name is always present.

Output is a structured record, not just a boolean:

```python
{ "day": "saturday", "time": "1-2PM", "venue": "Jurong West Sports Hall",
  "cost": None, "raw_text": "..." }
```

Structuring the output (rather than just pass/fail) is a deliberate v1
choice so venue/area filtering — explicitly out of scope now, per the user's
spec — can be bolted on later without reparsing raw text.

### Test fixtures (from the spec, covers both known bugs)

The 5 sample messages already in the spec file are used as-is for v1 test
fixtures: two SUPPLY messages with day names, one DEMAND message (negative
case for the supply/demand filter), one SUPPLY message with numeric-date-only
(exercises the `dateutil` fallback), and one DEMAND message with irregular
double-space whitespace (exercises the whitespace-tolerant demand regex). The
user has a larger 16-message set from an earlier conversation that can be
added to the fixture file later if real-world misses turn up; not required
for v1.

## Error handling

No custom alerting for v1. GitHub Actions' default failure-email-to-repo-owner
covers API failures, an expired userbot session, etc. This can be revisited
if failures turn out to be noisy or silent-failure-prone in practice.

## Testing

- `pytest` unit tests for `parser.py` against the 5 fixture messages above.
- `state.py` gets tests for trigger and dedup state transitions (vote count
  crossing 4, re-run not re-triggering, message ID dedup).
- `poll.py` and `watcher.py`'s Telegram/Telethon calls are mocked in tests —
  no live API dependency for the test suite.

## Open assumptions to revisit later

- "This week's listing" is scoped by message recency since the Thursday poll
  post, not by parsing an exact calendar date. If someone posts a listing
  unusually early (e.g. Tuesday, for the following weekend), it could be
  wrongly matched — acceptable tradeoff per the user, revisit if it causes a
  real false match.
- Area/venue filtering is deliberately deferred; the parser's structured
  output format is designed so this can be added later without reparsing.
- `watcher.py` self-checks the SGT time window rather than relying on precise
  cron-level UTC boundaries, to avoid subtle day-boundary bugs in the
  workflow YAML.

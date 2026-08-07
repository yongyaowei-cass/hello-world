# Badminton Bot — Stop Matching on Confirmation — Design

## Problem

Once someone actually books a court via PM with a listing's poster, the bot
keeps finding and posting more matching listings for that same day —
unnecessary spam in the group chat once the group's need for that day is
already met. There's no automatic way to detect a PM-based booking
confirmation (it happens entirely outside Telegram bots' visibility), so
this needs an explicit, manual signal from a friend.

## Scope

- Let anyone in the friends' group reply `/confirmed` to a posted match
  message to stop all further scanning/posting for that match's day.
- Out of scope: automatic confirmation detection, restricting who can
  confirm, confirming via anything other than a reply (buttons, other
  commands), un-confirming / reopening a day once stopped.

## Design

### Detecting a confirmation

The bot already polls `getUpdates` each run for vote-counting. This is
extended to also watch `"message"` updates in the friends' chat: a `message`
update whose `reply_to_message.message_id` is one of the bot's own posted
match IDs, and whose text (trimmed, case-insensitive) is `/confirmed`.
`telegram_bot.get_updates`'s `allowed_updates` filter widens from `["poll"]`
to `["poll", "message"]`.

**Single unified pass, not two loops**: vote-counting and confirmation
detection both consume the same `get_updates()` result. Rather than two
separate loops (which would double-track `last_update_id` and be an
unnecessary redundant pass over the same data), `watcher.py` gets one
update-processing pass that dispatches each update to a poll-handler or a
message-handler as appropriate, advancing `last_update_id` once per update
regardless of which handler applies.

### Tracking which day a posted match belongs to

`state.json`'s `posted_message_ids` (currently a flat list, used only for
dedup) becomes day-keyed: `{"saturday": [...ids], "sunday": [...ids]}`.
This is the only place that association can live — the message *text* isn't
stored in state, so there's no way to re-derive "which day was this" at
confirmation time without either storing it at post-time (this change) or
re-fetching the original message from Telegram (extra API call, and the
message could have changed or been deleted by then). `is_posted`/
`mark_posted` become day-scoped lookups into this structure; since a message
can only ever match one day (per `parser.parse_listing`'s single-day
result), a day-scoped dedup check is equivalent to the old global one, just
more precise.

### Stopping a confirmed day

New state field: `confirmed: {"saturday": false, "sunday": false}`,
alongside the existing `triggered` flag — `triggered` means "started
watching this day," `confirmed` means "a human explicitly said stop."
`_process_day` gains an early-return check for `confirmed` at the very top,
before the existing `triggered`/threshold gate.

**Avoiding a wasted listings fetch**: the existing `saturday_active`/
`sunday_active` computation (which gates whether the bot bothers calling
`listings_client.fetch_messages_since` at all — an expensive Telethon
history scan) currently only considers `triggered`/vote-threshold. It's
extended to also exclude confirmed days: a confirmed day no longer counts as
"active," so once *both* days are confirmed, the fetch is skipped entirely
for that run — not just the posting step. This mirrors the exact "avoid an
unnecessary Telethon fetch" fix already made once before for the doubled-fetch
issue in the Topics work.

### Acknowledgment

When a confirmation is processed, the bot replies in the same chat (e.g.
"Got it — stopped searching for Sunday courts 🏸") and — **critically** —
saves state immediately after handling that single update, not only at the
end of the run. This matches the existing incremental-save discipline
already used for match-posting (added after a real production incident):
without it, a crash between sending the acknowledgment and the run's final
`save_state` would leave `last_update_id` unadvanced, causing the same
confirmation reply to be reprocessed and a duplicate acknowledgment sent on
the next run.

### Edge cases

- Reply to a message that isn't one of the bot's posted matches: ignored,
  no-op.
- `/confirmed` reply to an already-confirmed day's match: idempotent no-op
  (already `true`, nothing further happens, no duplicate acknowledgment).
- Interaction with the pending "matches in a dedicated Topic" feature: works
  identically whether matches post to the main chat or a topic — replies
  within a topic still carry the same `reply_to_message` structure.
- Anyone in the friends' group can confirm — no restriction to a specific
  person (e.g. not limited to whoever the bot thinks "claimed" it), matching
  the trusted-small-group nature of this bot.

## Testing

- `state.py`: tests for the new day-keyed `posted_message_ids` shape,
  `is_posted`/`mark_posted` per day, and `is_confirmed`/`mark_confirmed`.
- `watcher.py`: unit tests for the unified update-processing pass — a poll
  update and a confirmation-reply update in the same batch are both handled
  correctly in one call; a confirmed day is excluded from
  `saturday_active`/`sunday_active` and no fetch happens when both days are
  confirmed; state is saved immediately after processing a confirmation
  (not only at the end of `main()`); a reply to an unrelated message is a
  no-op; a duplicate `/confirmed` reply to an already-confirmed day is a
  no-op with no duplicate acknowledgment.
- `telegram_bot.py`: test that `get_updates` requests `allowed_updates:
  ["poll", "message"]`.
- Manual verification: deployed straight to production per the pattern
  already established for this bot's other changes — the user will confirm
  live that replying `/confirmed` to a real match actually stops further
  matches for that day.

## Open assumptions to revisit later

- No un-confirm / reopen mechanism — if someone confirms by mistake, the
  only recovery today would be a manual state.json edit (same as the
  poll-deletion recovery done once already). Deliberately out of scope for
  v1; revisit if mis-confirmation turns out to be a real occurrence.
- `/confirmed` is a fixed, hardcoded keyword (no synonyms), matching how
  `POLL_QUESTION`/`POLL_OPTIONS` are already hardcoded constants in
  `poll.py` rather than configurable.

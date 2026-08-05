# Badminton Bot — Match Listings in a Dedicated Topic — Design

## Problem

The bot currently posts every matched court listing directly into the main
stream of the friends' group, alongside the weekly poll. In live production
use, a single trigger can surface a burst of matches at once (23 in one run
during launch-day testing) — flooding the main chat and burying the poll
question under a wall of match messages. The user wants matches routed to a
separate Telegram Topic within the same group, so the main chat stays quiet
(poll only) and interested friends check the dedicated topic instead.

## Scope

- Route match postings (not the poll) into a specific Telegram Topic within
  the friends' group.
- The poll continues to post to the main/General area of the group, exactly
  as today — no change to `poll.py` or poll-posting behavior.
- Out of scope: creating or managing the topic programmatically (the user
  creates it manually, one time); any change to matching/parsing/dedup logic;
  any change to the listings group side (only the friends' group gains a
  topic).

## Design

**Mechanism**: Telegram's Bot API `sendMessage` accepts an optional
`message_thread_id` parameter that routes a message into a specific Topic
within a forum-enabled group, instead of the default/General stream.
`sendPoll` doesn't take this parameter in this design — polls keep posting
to the main area unchanged.

**Config**: one new optional secret, `MATCHES_TOPIC_ID` — the topic ID of a
topic named **"Court Matches"**, created manually by the user in the real
friends' group (same one-time setup pattern as the group chat IDs
established earlier: create the topic in Telegram, run a small local script
using the Telethon session to read its topic ID, add it as a GitHub secret).
`config.py` gains `Config.matches_topic_id: int | None`, parsed from the env
var (absent or empty string → `None`, matching the existing pattern used for
other optional config like `VOTE_THRESHOLD`).

**Code changes**:
- `telegram_bot.send_message` gains an optional
  `message_thread_id: int | None = None` parameter. When set, it's passed
  through to the `sendMessage` API call (as `message_thread_id`); when
  `None`, the parameter is omitted entirely from the request (so behavior
  for any caller not using topics is completely unchanged).
- `watcher.py`'s match-posting call
  (`telegram_bot.send_message(cfg.bot_token, cfg.friends_chat_id, text)`)
  passes `cfg.matches_topic_id` as the new parameter.
- `poll.py` is untouched.

**Behavior**: main chat receives the poll only — completely silent
otherwise, per the user's explicit call (no "new match posted" nudge in
main chat). All match postings (including sender name and jump-link, from
the earlier sender-info feature) go into "Court Matches" instead.

**Rollout**: deployed directly to the real production friends' group, no
staging cycle first — the user's explicit call, given the extensive live
testing already completed on the core posting mechanism. The user will
separately gauge with friends whether the topic split actually improves the
chat experience.

## One-time manual setup (user, not code)

1. Create a Topic named "Court Matches" in the real friends' group (tap "+"
   in the group, same as creating any topic — requires the group to have
   Topics/Forum mode enabled first, which is not yet on for this group and
   needs enabling as part of this same step).
2. Run a small local script (same pattern as the earlier chat-ID lookup
   scripts) using the Telethon session to read the new topic's ID.
3. Add that ID as the `MATCHES_TOPIC_ID` GitHub repo secret.

No code changes are required to onboard the topic once the secret is set —
if `MATCHES_TOPIC_ID` is ever unset again, matches simply fall back to
posting in the main area (the same as today's behavior), since the
parameter is optional throughout.

## Testing

- `telegram_bot.py`: unit test that `send_message` includes
  `message_thread_id` in the request payload when passed, and omits it
  entirely when not passed (not just `None` in the payload — actually
  absent, since Telegram's API should not receive a null value for an
  unused optional parameter).
- `watcher.py`: unit test that the match-posting call passes
  `cfg.matches_topic_id` through to `telegram_bot.send_message`.
- `config.py`: unit tests for `matches_topic_id` — unset/empty → `None`,
  a real integer string → parsed as `int`.
- Manual verification: since this deploys straight to production, the user
  will manually confirm (via Telegram) that a real match lands in "Court
  Matches" and not the main chat, and that the poll still posts to the main
  chat as before.

## Open assumptions to revisit later

- No fallback/error handling is added for the case where `MATCHES_TOPIC_ID`
  is set but the topic itself has been deleted or is otherwise invalid —
  Telegram's API would return an error for `sendMessage`, which the bot
  already fails loudly on (per existing "no custom alerting" design), same
  as any other `sendMessage` failure.

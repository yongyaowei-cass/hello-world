# Badminton Bot Stop-on-Confirmation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let anyone in the friends' group reply `/confirmed` to a posted match to stop further scanning/posting for that day, and `/unconfirmed` to undo it, so the group stops getting spammed with matches once a court is already booked.

**Architecture:** Widen the bot's existing `getUpdates` polling to also watch `"message"` updates (replies), in one unified per-update loop alongside the existing poll-vote handling. A new per-day `confirmed` flag in state gates both the listings fetch and the per-day posting loop. `posted_message_ids` becomes day-keyed so a reply can be traced back to which day it belongs to.

**Tech Stack:** Same as the rest of the project — Python, `requests` (Bot API), pytest. No new dependencies.

**Spec:** [docs/superpowers/specs/2026-08-07-badminton-bot-stop-on-confirmation-design.md](../specs/2026-08-07-badminton-bot-stop-on-confirmation-design.md)

## Global Constraints

- `/confirmed` and `/unconfirmed` are fixed, hardcoded keywords (case-insensitive, trimmed) — not configurable.
- Anyone in the friends' group can confirm or unconfirm — no permission check.
- A confirmed day is excluded from `saturday_active`/`sunday_active`, so the (expensive) listings fetch is skipped entirely once a day is confirmed, not just the posting step.
- Vote-counting and confirmation-detection share ONE pass over ONE `get_updates()` call — never two separate loops over the same result.
- State is saved immediately after handling a confirmation/un-confirmation (not only at the end of the run), matching the existing incremental-save discipline used for match-posting.
- Unconfirming does not retroactively re-post already-posted listings (dedup via `posted_message_ids` still applies) — it only resumes scanning going forward.
- This repo's `state.json` is live in production. This plan's schema change (`posted_message_ids` list → dict) is NOT backward compatible with the current live file — Task 4 is a manual, non-code migration step and must not be skipped or reordered before the code tasks.

---

## Repo Context

Working directory for all tasks: `C:\Users\Yao Wei\badminton-bot` (existing repo, branch `master`). Read each file fully before editing — this plan shows the exact target content, but confirm the current file matches what's referenced here (paths/line numbers) before changing it, since other work may have landed in between.

---

### Task 1: Widen `get_updates` to also receive message replies

**Files:**
- Modify: `src/telegram_bot.py:29`
- Test: `tests/test_telegram_bot.py:40`

**Interfaces:**
- Consumes: nothing new.
- Produces: `telegram_bot.get_updates(token, offset)` now requests `allowed_updates=["poll", "message"]` instead of `["poll"]`. Signature and return shape unchanged.

- [ ] **Step 1: Update the failing test**

In `tests/test_telegram_bot.py`, change line 40 from:
```python
    assert kwargs["json"]["allowed_updates"] == ["poll"]
```
to:
```python
    assert kwargs["json"]["allowed_updates"] == ["poll", "message"]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pytest tests/test_telegram_bot.py::test_get_updates_returns_result_list -v`
Expected: FAIL — `assert ['poll'] == ['poll', 'message']`

- [ ] **Step 3: Implement the change**

In `src/telegram_bot.py`, change:
```python
def get_updates(token: str, offset: int) -> list[dict]:
    return _call(token, "getUpdates", offset=offset, timeout=0, allowed_updates=["poll"])
```
to:
```python
def get_updates(token: str, offset: int) -> list[dict]:
    return _call(token, "getUpdates", offset=offset, timeout=0, allowed_updates=["poll", "message"])
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pytest tests/test_telegram_bot.py -v`
Expected: PASS (4 passed)

- [ ] **Step 5: Commit**

```bash
git add src/telegram_bot.py tests/test_telegram_bot.py
git commit -m "feat: widen get_updates to also receive message replies"
```

---

### Task 2: Day-keyed dedup, confirmed flag, and day lookup in state.py

**Files:**
- Modify: `src/state.py` (full replacement below)
- Test: `tests/test_state.py` (full replacement below)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `state.DEFAULT_STATE["posted_message_ids"]` is now `{"saturday": [], "sunday": []}` (was `[]`).
  - `state.DEFAULT_STATE["confirmed"]` is new: `{"saturday": False, "sunday": False}`.
  - `state.is_posted(state, day, message_id) -> bool` (was `is_posted(state, message_id)`).
  - `state.mark_posted(state, day, message_id) -> None` (was `mark_posted(state, message_id)`).
  - `state.is_confirmed(state, day) -> bool` (new).
  - `state.mark_confirmed(state, day) -> None` (new).
  - `state.mark_unconfirmed(state, day) -> None` (new).
  - `state.find_day_for_message(state, message_id) -> str | None` (new) — returns `"saturday"`/`"sunday"` if `message_id` is in that day's `posted_message_ids`, else `None`.
  - `new_week_state(...)`'s signature and every other existing function's signature are unchanged.

- [ ] **Step 1: Replace `tests/test_state.py` with the failing tests**

```python
import json

from src import state


def test_load_state_missing_file_returns_default(tmp_path):
    path = str(tmp_path / "state.json")

    result = state.load_state(path)

    assert result["poll_id"] is None
    assert result["vote_counts"] == {"saturday": 0, "sunday": 0}
    assert result["triggered"] == {"saturday": False, "sunday": False}
    assert result["confirmed"] == {"saturday": False, "sunday": False}
    assert result["posted_message_ids"] == {"saturday": [], "sunday": []}


def test_default_state_independent_between_calls(tmp_path):
    path = str(tmp_path / "state.json")

    first = state.load_state(path)
    first["posted_message_ids"]["saturday"].append(999)
    first["triggered"]["saturday"] = True
    first["confirmed"]["sunday"] = True

    second = state.load_state(path)

    assert second["posted_message_ids"] == {"saturday": [], "sunday": []}
    assert second["triggered"]["saturday"] is False
    assert second["confirmed"]["sunday"] is False


def test_save_and_load_roundtrip(tmp_path):
    path = str(tmp_path / "state.json")
    original = state.new_week_state(
        poll_id="poll-1",
        poll_message_id=1234,
        poll_chat_id=-100999,
        poll_posted_at="2026-07-30T01:00:00Z",
        week_of="2026-08-01",
    )

    state.save_state(original, path)
    loaded = state.load_state(path)

    assert loaded == original
    with open(path, encoding="utf-8") as f:
        assert json.load(f) == original


def test_new_week_state_shape():
    result = state.new_week_state(
        poll_id="poll-1",
        poll_message_id=1234,
        poll_chat_id=-100999,
        poll_posted_at="2026-07-30T01:00:00Z",
        week_of="2026-08-01",
    )

    assert result["poll_id"] == "poll-1"
    assert result["poll_message_id"] == 1234
    assert result["poll_chat_id"] == -100999
    assert result["poll_posted_at"] == "2026-07-30T01:00:00Z"
    assert result["week_of"] == "2026-08-01"
    assert result["last_update_id"] == 0
    assert result["triggered"] == {"saturday": False, "sunday": False}
    assert result["confirmed"] == {"saturday": False, "sunday": False}
    assert result["posted_message_ids"] == {"saturday": [], "sunday": []}


def test_has_active_poll():
    fresh = state.load_state("does-not-exist.json")
    active = state.new_week_state("poll-1", 1234, -100999, "2026-07-30T01:00:00Z", "2026-08-01")

    assert state.has_active_poll(fresh) is False
    assert state.has_active_poll(active) is True


def test_mark_triggered_and_is_triggered():
    st = state.new_week_state("poll-1", 1234, -100999, "2026-07-30T01:00:00Z", "2026-08-01")

    assert state.is_triggered(st, "saturday") is False

    state.mark_triggered(st, "saturday")

    assert state.is_triggered(st, "saturday") is True
    assert state.is_triggered(st, "sunday") is False


def test_mark_posted_and_is_posted_dedup_per_day():
    st = state.new_week_state("poll-1", 1234, -100999, "2026-07-30T01:00:00Z", "2026-08-01")

    assert state.is_posted(st, "saturday", 555) is False

    state.mark_posted(st, "saturday", 555)

    assert state.is_posted(st, "saturday", 555) is True
    assert state.is_posted(st, "sunday", 555) is False


def test_mark_confirmed_and_is_confirmed():
    st = state.new_week_state("poll-1", 1234, -100999, "2026-07-30T01:00:00Z", "2026-08-01")

    assert state.is_confirmed(st, "sunday") is False

    state.mark_confirmed(st, "sunday")

    assert state.is_confirmed(st, "sunday") is True
    assert state.is_confirmed(st, "saturday") is False


def test_mark_unconfirmed_reverses_confirmed():
    st = state.new_week_state("poll-1", 1234, -100999, "2026-07-30T01:00:00Z", "2026-08-01")
    state.mark_confirmed(st, "sunday")

    state.mark_unconfirmed(st, "sunday")

    assert state.is_confirmed(st, "sunday") is False


def test_find_day_for_message():
    st = state.new_week_state("poll-1", 1234, -100999, "2026-07-30T01:00:00Z", "2026-08-01")
    state.mark_posted(st, "sunday", 501)
    state.mark_posted(st, "saturday", 601)

    assert state.find_day_for_message(st, 501) == "sunday"
    assert state.find_day_for_message(st, 601) == "saturday"
    assert state.find_day_for_message(st, 999) is None
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/test_state.py -v`
Expected: FAIL — several `AttributeError`/`KeyError`/`TypeError` (missing `confirmed` key, `is_posted`/`mark_posted` called with 3 args against a 2-arg function, `is_confirmed`/`mark_confirmed`/`mark_unconfirmed`/`find_day_for_message` not defined)

- [ ] **Step 3: Replace `src/state.py`**

```python
import copy
import json
import os

DEFAULT_STATE = {
    "week_of": None,
    "poll_id": None,
    "poll_message_id": None,
    "poll_chat_id": None,
    "poll_posted_at": None,
    "last_update_id": 0,
    "vote_counts": {"saturday": 0, "sunday": 0},
    "triggered": {"saturday": False, "sunday": False},
    "confirmed": {"saturday": False, "sunday": False},
    "posted_message_ids": {"saturday": [], "sunday": []},
}


def load_state(path: str) -> dict:
    if not os.path.exists(path):
        return copy.deepcopy(DEFAULT_STATE)
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_state(state: dict, path: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)


def new_week_state(
    poll_id: str,
    poll_message_id: int,
    poll_chat_id: int,
    poll_posted_at: str,
    week_of: str,
) -> dict:
    fresh = copy.deepcopy(DEFAULT_STATE)
    fresh.update(
        {
            "week_of": week_of,
            "poll_id": poll_id,
            "poll_message_id": poll_message_id,
            "poll_chat_id": poll_chat_id,
            "poll_posted_at": poll_posted_at,
        }
    )
    return fresh


def has_active_poll(state: dict) -> bool:
    return state.get("poll_id") is not None


def is_triggered(state: dict, day: str) -> bool:
    return state["triggered"].get(day, False)


def mark_triggered(state: dict, day: str) -> None:
    state["triggered"][day] = True


def is_confirmed(state: dict, day: str) -> bool:
    return state["confirmed"].get(day, False)


def mark_confirmed(state: dict, day: str) -> None:
    state["confirmed"][day] = True


def mark_unconfirmed(state: dict, day: str) -> None:
    state["confirmed"][day] = False


def is_posted(state: dict, day: str, message_id: int) -> bool:
    return message_id in state["posted_message_ids"][day]


def mark_posted(state: dict, day: str, message_id: int) -> None:
    state["posted_message_ids"][day].append(message_id)


def find_day_for_message(state: dict, message_id: int) -> str | None:
    for day, ids in state["posted_message_ids"].items():
        if message_id in ids:
            return day
    return None
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/test_state.py -v`
Expected: PASS (10 passed)

- [ ] **Step 5: Run the full suite to check for breakage elsewhere (expected — watcher.py and its tests are not updated until Task 3)**

Run: `pytest -v`
Expected: FAIL in `tests/test_watcher.py` (the old `posted_message_ids: []` fixtures and 2-arg `is_posted`/`mark_posted` calls in `src/watcher.py` don't match the new schema yet). This is expected at this point in the plan — Task 3 fixes it. Do not attempt to fix `watcher.py` in this task.

- [ ] **Step 6: Commit**

```bash
git add src/state.py tests/test_state.py
git commit -m "feat: day-keyed dedup and confirmed flag in state.py"
```

---

### Task 3: Unified update processing, confirm/unconfirm handling, and confirmed gating in watcher.py

**Files:**
- Modify: `src/watcher.py` (full replacement below)
- Test: `tests/test_watcher.py` (full replacement below)

**Interfaces:**
- Consumes: `state.is_confirmed`, `state.mark_confirmed`, `state.mark_unconfirmed`, `state.find_day_for_message`, `state.is_posted(st, day, id)`, `state.mark_posted(st, day, id)` — all from Task 2. `telegram_bot.get_updates` now delivers `"message"` updates too, from Task 1.
- Produces: `watcher.CONFIRM_KEYWORD = "/confirmed"`, `watcher.UNCONFIRM_KEYWORD = "/unconfirmed"`. `_update_vote_counts` is replaced by `_process_updates(cfg, st) -> None` (same call site in `main()`, new name and broader behavior). New helpers `_handle_poll_update(st, poll) -> None` and `_handle_message_update(cfg, st, message) -> None`. `_process_day`'s signature is unchanged; it now checks `state.is_confirmed` first.

- [ ] **Step 1: Replace `tests/test_watcher.py` with the updated + new failing tests**

```python
import copy
from datetime import datetime, timezone
from unittest.mock import patch

import pytest

from src import poll, watcher
from src.config import Config


def _fake_config(vote_threshold=4, force_run=False):
    return Config(
        bot_token="tok",
        friends_chat_id=-100111,
        listings_chat_id=-100222,
        api_id=1,
        api_hash="hash",
        userbot_session="session",
        vote_threshold=vote_threshold,
        state_path="state.json",
        force_run=force_run,
    )


def test_in_watch_window_true_during_saturday_afternoon():
    now_sgt = datetime(2026, 8, 1, 14, 0)  # Saturday
    assert watcher.in_watch_window(now_sgt) is True


def test_in_watch_window_false_on_monday():
    now_sgt = datetime(2026, 8, 3, 14, 0)  # Monday
    assert watcher.in_watch_window(now_sgt) is False


def test_in_watch_window_false_outside_hours():
    now_sgt = datetime(2026, 8, 1, 2, 0)  # Saturday, 2am
    assert watcher.in_watch_window(now_sgt) is False


def test_extract_vote_counts_combines_both_option():
    poll_options = [
        {"text": "Saturday", "voter_count": 2},
        {"text": "Sunday", "voter_count": 1},
        {"text": "Both", "voter_count": 3},
        {"text": "Can't make it", "voter_count": 0},
    ]

    result = watcher.extract_vote_counts(poll_options)

    assert result == {"saturday": 5, "sunday": 4}


def test_main_noop_outside_watch_window():
    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state") as mock_load_state,
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 3, 14, 0, tzinfo=watcher.SGT)
        watcher.main()

    mock_load_state.assert_not_called()


def test_main_force_run_bypasses_watch_window():
    """A manually-triggered run (FORCE_RUN=true -> cfg.force_run=True) must
    proceed with real work even when invoked outside the normal Thu-Sun
    8am-11pm watch window, so UAT/manual workflow_dispatch runs aren't a
    silent no-op."""
    with (
        patch("src.watcher.config.load_config", return_value=_fake_config(force_run=True)),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value={"poll_id": None}) as mock_load_state,
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 3, 14, 0, tzinfo=watcher.SGT)
        watcher.main()

    mock_load_state.assert_called_once()


def test_main_noop_when_no_active_poll():
    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value={"poll_id": None}),
        patch("src.watcher.telegram_bot.get_updates") as mock_get_updates,
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        watcher.main()

    mock_get_updates.assert_not_called()


def test_main_triggers_and_posts_matching_supply_listing_once():
    st = {
        "poll_id": "poll-abc",
        "poll_posted_at": "2026-07-30T01:00:00+00:00",
        "last_update_id": 10,
        "vote_counts": {"saturday": 0, "sunday": 0},
        "triggered": {"saturday": False, "sunday": False},
        "confirmed": {"saturday": False, "sunday": False},
        "posted_message_ids": {"saturday": [], "sunday": []},
    }
    updates = [
        {
            "update_id": 11,
            "poll": {
                "id": "poll-abc",
                "options": [
                    {"text": "Saturday", "voter_count": 4},
                    {"text": "Sunday", "voter_count": 0},
                    {"text": "Both", "voter_count": 0},
                    {"text": "Can't make it", "voter_count": 0},
                ],
            },
        }
    ]
    listings = [
        {
            "id": 501,
            "text": "Letting go court, Saturday 3pm, PM me",
            "date": None,
            "sender_name": "Alice (@alice_w)",
            "link": "https://t.me/c/222/501",
        },
        {
            "id": 502,
            "text": "LF court Saturday, PM me",
            "date": None,
            "sender_name": "Bob Tan",
            "link": "https://t.me/c/222/502",
        },
    ]

    saved_snapshots = []

    def _record_save(state, path):
        saved_snapshots.append(copy.deepcopy(state))

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates", return_value=updates),
        patch("src.watcher.listings_client.fetch_messages_since", return_value=listings),
        patch("src.watcher.telegram_bot.send_message") as mock_send_message,
        patch("src.watcher.state.save_state", side_effect=_record_save),
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        mock_datetime.fromisoformat.side_effect = datetime.fromisoformat
        watcher.main()

    mock_send_message.assert_called_once()
    call_args = mock_send_message.call_args[0]
    assert call_args[0] == "tok"
    assert call_args[1] == -100111
    assert "Letting go court, Saturday 3pm, PM me" in call_args[2]
    assert "Posted by: Alice (@alice_w)" in call_args[2]
    assert "https://t.me/c/222/501" in call_args[2]

    # New checkpoint sequence under continuous scanning (Fix C):
    # 1) mark_triggered saved BEFORE any listing is scanned/posted,
    # 2) the successful send/mark_posted saved next,
    # 3) main()'s unconditional final save (unchanged from before).
    assert len(saved_snapshots) == 3
    assert saved_snapshots[0]["triggered"]["saturday"] is True
    assert saved_snapshots[0]["posted_message_ids"] == {"saturday": [], "sunday": []}
    assert saved_snapshots[1]["triggered"]["saturday"] is True
    assert saved_snapshots[1]["posted_message_ids"] == {"saturday": [501], "sunday": []}
    assert saved_snapshots[-1]["triggered"]["saturday"] is True
    assert saved_snapshots[-1]["posted_message_ids"] == {"saturday": [501], "sunday": []}


def test_main_persists_state_after_each_send_before_crash():
    """A crash mid-loop (after one send succeeds, before the next) must not
    lose the fact that the first message was already posted. Otherwise the
    next cron run re-fetches, re-matches, and re-sends the same listing."""
    st = {
        "poll_id": "poll-abc",
        "poll_posted_at": "2026-07-30T01:00:00+00:00",
        "last_update_id": 10,
        "vote_counts": {"saturday": 0, "sunday": 0},
        "triggered": {"saturday": False, "sunday": False},
        "confirmed": {"saturday": False, "sunday": False},
        "posted_message_ids": {"saturday": [], "sunday": []},
    }
    updates = [
        {
            "update_id": 11,
            "poll": {
                "id": "poll-abc",
                "options": [
                    {"text": "Saturday", "voter_count": 4},
                    {"text": "Sunday", "voter_count": 0},
                    {"text": "Both", "voter_count": 0},
                    {"text": "Can't make it", "voter_count": 0},
                ],
            },
        }
    ]
    listings = [
        {
            "id": 501,
            "text": "Letting go court, Saturday 3pm, PM me",
            "date": None,
            "sender_name": "Alice (@alice_w)",
            "link": "https://t.me/c/222/501",
        },
        {
            "id": 502,
            "text": "Letting go court, Saturday 5pm, PM me",
            "date": None,
            "sender_name": "Bob Tan",
            "link": "https://t.me/c/222/502",
        },
    ]

    saved_snapshots = []

    def _record_save(state, path):
        saved_snapshots.append(copy.deepcopy(state))

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates", return_value=updates),
        patch("src.watcher.listings_client.fetch_messages_since", return_value=listings),
        patch(
            "src.watcher.telegram_bot.send_message",
            side_effect=[None, RuntimeError("boom")],
        ),
        patch("src.watcher.state.save_state", side_effect=_record_save),
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        mock_datetime.fromisoformat.side_effect = datetime.fromisoformat

        with pytest.raises(RuntimeError):
            watcher.main()

    assert saved_snapshots, "save_state should have been called before the crash propagated"
    assert saved_snapshots[0]["triggered"]["saturday"] is True
    assert saved_snapshots[0]["posted_message_ids"] == {"saturday": [], "sunday": []}
    assert saved_snapshots[-1]["posted_message_ids"] == {"saturday": [501], "sunday": []}
    assert saved_snapshots[-1]["triggered"]["saturday"] is True


def test_main_continues_scanning_already_triggered_day_and_posts_new_match():
    """Fix C: a day that was already triggered on a previous run must keep
    being scanned on every subsequent run, not just once at the moment its
    vote count first crossed the threshold."""
    st = {
        "poll_id": "poll-abc",
        "poll_posted_at": "2026-07-30T01:00:00+00:00",
        "last_update_id": 10,
        "vote_counts": {"saturday": 4, "sunday": 0},
        "triggered": {"saturday": True, "sunday": False},
        "confirmed": {"saturday": False, "sunday": False},
        "posted_message_ids": {"saturday": [], "sunday": []},
    }
    listings = [
        {
            "id": 601,
            "text": "Letting go court, Saturday 3pm, PM me",
            "date": None,
            "sender_name": "Carol (@carol_c)",
            "link": "https://t.me/c/222/601",
        },
    ]

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates", return_value=[]),
        patch("src.watcher.listings_client.fetch_messages_since", return_value=listings),
        patch("src.watcher.telegram_bot.send_message") as mock_send_message,
        patch("src.watcher.state.save_state") as mock_save_state,
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        mock_datetime.fromisoformat.side_effect = datetime.fromisoformat
        watcher.main()

    mock_send_message.assert_called_once()
    call_args = mock_send_message.call_args[0]
    assert "Letting go court, Saturday 3pm, PM me" in call_args[2]
    assert "Posted by: Carol (@carol_c)" in call_args[2]
    assert "https://t.me/c/222/601" in call_args[2]
    saved_state = mock_save_state.call_args[0][0]
    assert saved_state["posted_message_ids"] == {"saturday": [601], "sunday": []}


def test_main_fetches_messages_once_when_both_days_active():
    """fetch_messages_since must be called at most once per main() run, with
    its result shared across both days."""
    st = {
        "poll_id": "poll-abc",
        "poll_posted_at": "2026-07-30T01:00:00+00:00",
        "last_update_id": 10,
        "vote_counts": {"saturday": 4, "sunday": 4},
        "triggered": {"saturday": False, "sunday": False},
        "confirmed": {"saturday": False, "sunday": False},
        "posted_message_ids": {"saturday": [], "sunday": []},
    }
    listings = [
        {
            "id": 501,
            "text": "Letting go court, Saturday 3pm, PM me",
            "date": None,
            "sender_name": "Alice (@alice_w)",
            "link": "https://t.me/c/222/501",
        },
        {
            "id": 502,
            "text": "Letting go court, Sunday 5pm, PM me",
            "date": None,
            "sender_name": "Bob Tan",
            "link": "https://t.me/c/222/502",
        },
    ]

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates", return_value=[]),
        patch(
            "src.watcher.listings_client.fetch_messages_since", return_value=listings
        ) as mock_fetch,
        patch("src.watcher.telegram_bot.send_message") as mock_send_message,
        patch("src.watcher.state.save_state"),
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        mock_datetime.fromisoformat.side_effect = datetime.fromisoformat
        watcher.main()

    mock_fetch.assert_called_once()
    assert mock_send_message.call_count == 2
    sent_texts = [call.args[2] for call in mock_send_message.call_args_list]
    assert any("Saturday 3pm" in text for text in sent_texts)
    assert any("Sunday 5pm" in text for text in sent_texts)
    assert any("Posted by: Alice (@alice_w)" in text and "https://t.me/c/222/501" in text for text in sent_texts)
    assert any("Posted by: Bob Tan" in text and "https://t.me/c/222/502" in text for text in sent_texts)


def test_main_fetches_once_when_only_saturday_active():
    st = {
        "poll_id": "poll-abc",
        "poll_posted_at": "2026-07-30T01:00:00+00:00",
        "last_update_id": 10,
        "vote_counts": {"saturday": 4, "sunday": 0},
        "triggered": {"saturday": False, "sunday": False},
        "confirmed": {"saturday": False, "sunday": False},
        "posted_message_ids": {"saturday": [], "sunday": []},
    }
    listings = [
        {
            "id": 501,
            "text": "Letting go court, Saturday 3pm, PM me",
            "date": None,
            "sender_name": "Alice (@alice_w)",
            "link": "https://t.me/c/222/501",
        },
    ]

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates", return_value=[]),
        patch(
            "src.watcher.listings_client.fetch_messages_since", return_value=listings
        ) as mock_fetch,
        patch("src.watcher.telegram_bot.send_message") as mock_send_message,
        patch("src.watcher.state.save_state"),
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        mock_datetime.fromisoformat.side_effect = datetime.fromisoformat
        watcher.main()

    mock_fetch.assert_called_once()
    mock_send_message.assert_called_once()


def test_main_does_not_fetch_when_neither_day_active():
    st = {
        "poll_id": "poll-abc",
        "poll_posted_at": "2026-07-30T01:00:00+00:00",
        "last_update_id": 10,
        "vote_counts": {"saturday": 1, "sunday": 0},
        "triggered": {"saturday": False, "sunday": False},
        "confirmed": {"saturday": False, "sunday": False},
        "posted_message_ids": {"saturday": [], "sunday": []},
    }

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates", return_value=[]),
        patch(
            "src.watcher.listings_client.fetch_messages_since"
        ) as mock_fetch,
        patch("src.watcher.telegram_bot.send_message") as mock_send_message,
        patch("src.watcher.state.save_state"),
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        mock_datetime.fromisoformat.side_effect = datetime.fromisoformat
        watcher.main()

    mock_fetch.assert_not_called()
    mock_send_message.assert_not_called()


def test_main_noop_when_poll_is_stale():
    st = {
        "poll_id": "poll-abc",
        "poll_posted_at": "2026-07-20T01:00:00+00:00",
        "last_update_id": 10,
        "vote_counts": {"saturday": 0, "sunday": 0},
        "triggered": {"saturday": False, "sunday": False},
        "confirmed": {"saturday": False, "sunday": False},
        "posted_message_ids": {"saturday": [], "sunday": []},
    }

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates") as mock_get_updates,
        patch("src.watcher.state.save_state") as mock_save_state,
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        mock_datetime.fromisoformat.side_effect = datetime.fromisoformat
        watcher.main()

    mock_get_updates.assert_not_called()
    mock_save_state.assert_not_called()


def test_main_does_not_match_next_weeks_saturday_listing_when_run_on_sunday():
    """Weekend-validation is anchored to the poll's own (fixed Thursday)
    post time, converted to SGT, not to real "now" at the moment the
    watcher happens to run."""
    st = {
        "poll_id": "poll-abc",
        "poll_posted_at": "2026-07-30T01:00:00+00:00",  # Thursday (UTC)
        "last_update_id": 10,
        "vote_counts": {"saturday": 4, "sunday": 0},
        "triggered": {"saturday": False, "sunday": False},
        "confirmed": {"saturday": False, "sunday": False},
        "posted_message_ids": {"saturday": [], "sunday": []},
    }
    listings = [
        {
            "id": 701,
            "text": "Letting go court, 8th August, PM me",
            "date": None,
            "sender_name": "Dave (@dave_d)",
            "link": "https://t.me/c/222/701",
        },
    ]

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_watcher_datetime,
        patch("src.parser.datetime") as mock_parser_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates", return_value=[]),
        patch("src.watcher.listings_client.fetch_messages_since", return_value=listings),
        patch("src.watcher.telegram_bot.send_message") as mock_send_message,
        patch("src.watcher.state.save_state"),
    ):
        mock_watcher_datetime.now.return_value = datetime(2026, 8, 2, 14, 0, tzinfo=watcher.SGT)
        mock_watcher_datetime.fromisoformat.side_effect = datetime.fromisoformat
        mock_parser_datetime.now.return_value = datetime(2026, 8, 2, 14, 0)

        watcher.main()

    mock_send_message.assert_not_called()


def test_poll_options_order_matches_positional_assumption():
    assert poll.POLL_OPTIONS[:3] == ["Saturday", "Sunday", "Both"]


def test_confirmed_reply_stops_day_and_sends_acknowledgment():
    st = {
        "poll_id": "poll-abc",
        "poll_posted_at": "2026-07-30T01:00:00+00:00",
        "last_update_id": 10,
        "vote_counts": {"saturday": 0, "sunday": 4},
        "triggered": {"saturday": False, "sunday": True},
        "confirmed": {"saturday": False, "sunday": False},
        "posted_message_ids": {"saturday": [], "sunday": [501]},
    }
    updates = [
        {
            "update_id": 11,
            "message": {
                "chat": {"id": -100111},
                "text": "/confirmed",
                "reply_to_message": {"message_id": 501},
            },
        }
    ]

    saved_snapshots = []

    def _record_save(state, path):
        saved_snapshots.append(copy.deepcopy(state))

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates", return_value=updates),
        patch("src.watcher.listings_client.fetch_messages_since") as mock_fetch,
        patch("src.watcher.telegram_bot.send_message") as mock_send_message,
        patch("src.watcher.state.save_state", side_effect=_record_save),
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        mock_datetime.fromisoformat.side_effect = datetime.fromisoformat
        watcher.main()

    assert saved_snapshots, "save_state should have been called after processing the confirmation"
    assert saved_snapshots[0]["confirmed"]["sunday"] is True
    mock_send_message.assert_called_once_with(
        "tok", -100111, "Got it \u2014 stopped searching for Sunday courts \U0001f3f8"
    )
    mock_fetch.assert_not_called()


def test_unconfirmed_reply_resumes_day_and_sends_acknowledgment():
    st = {
        "poll_id": "poll-abc",
        "poll_posted_at": "2026-07-30T01:00:00+00:00",
        "last_update_id": 10,
        "vote_counts": {"saturday": 0, "sunday": 4},
        "triggered": {"saturday": False, "sunday": True},
        "confirmed": {"saturday": False, "sunday": True},
        "posted_message_ids": {"saturday": [], "sunday": [501]},
    }
    updates = [
        {
            "update_id": 11,
            "message": {
                "chat": {"id": -100111},
                "text": "/unconfirmed",
                "reply_to_message": {"message_id": 501},
            },
        }
    ]

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates", return_value=updates),
        patch("src.watcher.listings_client.fetch_messages_since", return_value=[]) as mock_fetch,
        patch("src.watcher.telegram_bot.send_message") as mock_send_message,
        patch("src.watcher.state.save_state"),
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        mock_datetime.fromisoformat.side_effect = datetime.fromisoformat
        watcher.main()

    assert st["confirmed"]["sunday"] is False
    mock_send_message.assert_called_once_with(
        "tok", -100111, "Got it \u2014 resumed searching for Sunday courts \U0001f3f8"
    )
    mock_fetch.assert_called_once()


def test_confirmed_reply_to_unrelated_message_is_noop():
    st = {
        "poll_id": "poll-abc",
        "poll_posted_at": "2026-07-30T01:00:00+00:00",
        "last_update_id": 10,
        "vote_counts": {"saturday": 0, "sunday": 0},
        "triggered": {"saturday": False, "sunday": False},
        "confirmed": {"saturday": False, "sunday": False},
        "posted_message_ids": {"saturday": [], "sunday": []},
    }
    updates = [
        {
            "update_id": 11,
            "message": {
                "chat": {"id": -100111},
                "text": "/confirmed",
                "reply_to_message": {"message_id": 999},
            },
        }
    ]

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates", return_value=updates),
        patch("src.watcher.listings_client.fetch_messages_since") as mock_fetch,
        patch("src.watcher.telegram_bot.send_message") as mock_send_message,
        patch("src.watcher.state.save_state"),
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        mock_datetime.fromisoformat.side_effect = datetime.fromisoformat
        watcher.main()

    assert st["confirmed"] == {"saturday": False, "sunday": False}
    mock_send_message.assert_not_called()
    mock_fetch.assert_not_called()


def test_duplicate_confirmed_reply_is_noop_no_duplicate_ack():
    st = {
        "poll_id": "poll-abc",
        "poll_posted_at": "2026-07-30T01:00:00+00:00",
        "last_update_id": 10,
        "vote_counts": {"saturday": 0, "sunday": 4},
        "triggered": {"saturday": False, "sunday": True},
        "confirmed": {"saturday": False, "sunday": True},
        "posted_message_ids": {"saturday": [], "sunday": [501]},
    }
    updates = [
        {
            "update_id": 11,
            "message": {
                "chat": {"id": -100111},
                "text": "/confirmed",
                "reply_to_message": {"message_id": 501},
            },
        }
    ]

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates", return_value=updates),
        patch("src.watcher.listings_client.fetch_messages_since") as mock_fetch,
        patch("src.watcher.telegram_bot.send_message") as mock_send_message,
        patch("src.watcher.state.save_state"),
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        mock_datetime.fromisoformat.side_effect = datetime.fromisoformat
        watcher.main()

    mock_send_message.assert_not_called()
    mock_fetch.assert_not_called()


def test_process_day_skips_confirmed_day_even_with_matching_messages():
    st = {
        "triggered": {"saturday": False, "sunday": True},
        "confirmed": {"saturday": False, "sunday": True},
        "vote_counts": {"saturday": 0, "sunday": 4},
        "posted_message_ids": {"saturday": [], "sunday": []},
    }
    messages = [
        {
            "id": 501,
            "text": "Letting go court, Sunday 3pm, PM me",
            "date": None,
            "sender_name": "Alice (@alice_w)",
            "link": "https://t.me/c/222/501",
        },
    ]

    with (
        patch("src.watcher.telegram_bot.send_message") as mock_send_message,
        patch("src.watcher.state.save_state") as mock_save_state,
    ):
        watcher._process_day(
            _fake_config(), st, "sunday", messages, datetime(2026, 7, 30, 9, 0, tzinfo=watcher.SGT)
        )

    mock_send_message.assert_not_called()
    mock_save_state.assert_not_called()
    assert st["posted_message_ids"]["sunday"] == []
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/test_watcher.py -v`
Expected: FAIL — multiple failures (old `posted_message_ids: []` shape vs new schema, `is_posted`/`mark_posted` call-signature mismatch in the not-yet-updated `src/watcher.py`, new confirm/unconfirm tests failing since the handling doesn't exist yet)

- [ ] **Step 3: Replace `src/watcher.py`**

```python
from datetime import datetime, timedelta, timezone

from src import config, listings_client, parser, state, telegram_bot

SGT = timezone(timedelta(hours=8))
CONFIRM_KEYWORD = "/confirmed"
UNCONFIRM_KEYWORD = "/unconfirmed"


def in_watch_window(now_sgt: datetime) -> bool:
    return now_sgt.weekday() in (3, 4, 5, 6) and 8 <= now_sgt.hour < 23


def extract_vote_counts(poll_options: list[dict]) -> dict:
    saturday_votes = poll_options[0]["voter_count"]
    sunday_votes = poll_options[1]["voter_count"]
    both_votes = poll_options[2]["voter_count"]
    return {
        "saturday": saturday_votes + both_votes,
        "sunday": sunday_votes + both_votes,
    }


def _handle_poll_update(st: dict, poll: dict) -> None:
    if poll["id"] != st["poll_id"]:
        return
    st["vote_counts"] = extract_vote_counts(poll["options"])


def _handle_message_update(cfg: config.Config, st: dict, message: dict) -> None:
    if message.get("chat", {}).get("id") != cfg.friends_chat_id:
        return
    reply_to = message.get("reply_to_message")
    if not reply_to:
        return
    day = state.find_day_for_message(st, reply_to["message_id"])
    if day is None:
        return

    text = (message.get("text") or "").strip().lower()
    if text == CONFIRM_KEYWORD:
        if state.is_confirmed(st, day):
            return
        state.mark_confirmed(st, day)
        state.save_state(st, cfg.state_path)
        telegram_bot.send_message(
            cfg.bot_token,
            cfg.friends_chat_id,
            f"Got it \u2014 stopped searching for {day.capitalize()} courts \U0001f3f8",
        )
    elif text == UNCONFIRM_KEYWORD:
        if not state.is_confirmed(st, day):
            return
        state.mark_unconfirmed(st, day)
        state.save_state(st, cfg.state_path)
        telegram_bot.send_message(
            cfg.bot_token,
            cfg.friends_chat_id,
            f"Got it \u2014 resumed searching for {day.capitalize()} courts \U0001f3f8",
        )


def _process_updates(cfg: config.Config, st: dict) -> None:
    updates = telegram_bot.get_updates(cfg.bot_token, st["last_update_id"] + 1)
    for update in updates:
        st["last_update_id"] = max(st["last_update_id"], update["update_id"])
        poll = update.get("poll")
        if poll:
            _handle_poll_update(st, poll)
            continue
        message = update.get("message")
        if message:
            _handle_message_update(cfg, st, message)


def _process_day(
    cfg: config.Config, st: dict, day: str, messages: list[dict], reference_date: datetime
) -> None:
    if state.is_confirmed(st, day):
        return

    if not state.is_triggered(st, day):
        if st["vote_counts"][day] < cfg.vote_threshold:
            return
        state.mark_triggered(st, day)
        state.save_state(st, cfg.state_path)

    for message in messages:
        listing = parser.parse_listing(message["text"], reference_date=reference_date)
        if listing is None or listing["day"] != day:
            continue
        if state.is_posted(st, day, message["id"]):
            continue
        text = (
            f"\U0001f3f8 Match for {day.capitalize()}:\n\n"
            f"{listing['raw_text']}\n\n"
            f"Posted by: {message['sender_name']}\n"
            f"{message['link']}"
        )
        telegram_bot.send_message(cfg.bot_token, cfg.friends_chat_id, text)
        state.mark_posted(st, day, message["id"])
        state.save_state(st, cfg.state_path)


def main() -> None:
    cfg = config.load_config()
    now_sgt = datetime.now(SGT)
    if not cfg.force_run and not in_watch_window(now_sgt):
        return

    st = state.load_state(cfg.state_path)
    if not state.has_active_poll(st):
        return

    poll_posted_at = datetime.fromisoformat(st["poll_posted_at"])
    if datetime.now(timezone.utc) - poll_posted_at > timedelta(days=7):
        return

    poll_posted_at_sgt = poll_posted_at.astimezone(SGT)

    _process_updates(cfg, st)

    saturday_active = not state.is_confirmed(st, "saturday") and (
        state.is_triggered(st, "saturday") or st["vote_counts"]["saturday"] >= cfg.vote_threshold
    )
    sunday_active = not state.is_confirmed(st, "sunday") and (
        state.is_triggered(st, "sunday") or st["vote_counts"]["sunday"] >= cfg.vote_threshold
    )

    messages = []
    if saturday_active or sunday_active:
        messages = listings_client.fetch_messages_since(
            cfg.api_id, cfg.api_hash, cfg.userbot_session, cfg.listings_chat_id, poll_posted_at
        )

    _process_day(cfg, st, "saturday", messages, poll_posted_at_sgt)
    _process_day(cfg, st, "sunday", messages, poll_posted_at_sgt)
    state.save_state(st, cfg.state_path)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/test_watcher.py -v`
Expected: PASS (21 passed)

- [ ] **Step 5: Run the full suite**

Run: `pytest -v`
Expected: PASS (all tests across every module — 64 total: the 56-test baseline at the start of this plan, plus 3 net-new tests in Task 2's `test_state.py` and 5 net-new tests in this task's `test_watcher.py`. If the baseline has changed since this plan was written, e.g. due to other work landing in between, the exact number will differ — the actual requirement is 0 failures, not this specific count.)

- [ ] **Step 6: Commit**

```bash
git add src/watcher.py tests/test_watcher.py
git commit -m "feat: confirm/unconfirm via reply, unified update loop, confirmed gating"
```

---

### Task 4: Manual production state migration (no code)

This is the one non-code task in this plan — it exists because the live `state.json` in the production repo predates this plan's schema change, and `load_state` does no automatic migration (deliberately, per the design's "no automatic migration code" YAGNI call — this transition happens exactly once).

**Files:** none (direct edit of the live `state.json` on `master`, same pattern as the earlier production state recovery already done once in this repo's history).

- [ ] **Step 1: Re-read the current live `state.json`** (`C:\Users\Yao Wei\badminton-bot\state.json`, after pulling latest `master`) immediately before writing, to confirm it still matches what's shown below — real production state may have changed since this plan was written (the watcher runs on its own schedule). If it has changed, redo Step 3 using the freshly-read values instead of the ones below; do not write stale data.

  As of when this plan was written, the live file was:
  ```json
  {
    "week_of": "2026-08-03",
    "poll_id": "6307421355511907907",
    "poll_message_id": 11,
    "poll_chat_id": -4254631451,
    "poll_posted_at": "2026-08-03T16:52:05.253506+00:00",
    "last_update_id": 278446642,
    "vote_counts": {"saturday": 2, "sunday": 6},
    "triggered": {"saturday": false, "sunday": true},
    "posted_message_ids": [202741, 202697, 202672, 202649, 202588, 202529, 202528, 202476, 202467, 202465, 202441, 202371, 202290, 202262, 202240, 202235, 202208, 202139, 202052, 202039, 201981, 201969, 201940, 202772, 202766, 203186, 203155, 203151, 203143, 203129, 203056, 203036, 202990, 202972, 202971, 202953, 202856, 202836, 202826, 202774, 203259, 203252, 203249, 203242, 203313, 203365, 203364, 203356]
  }
  ```
  `triggered.saturday` is `false` and `triggered.sunday` is `true` — Saturday has never triggered this week, so every one of these 48 IDs unambiguously belongs to Sunday's `posted_message_ids`; Saturday's list starts empty. (If a re-read in Step 3 shows `triggered.saturday` has since become `true` too, the split can no longer be recovered exactly from the old flat list — stop and ask the user how to proceed rather than guessing.)

- [ ] **Step 2: Confirm with the user before writing to the live file** — this changes real production state; get an explicit go-ahead, same as every other live-state edit made in this repo's history.

- [ ] **Step 3: Write the migrated content** (using the freshly re-read values from Step 1 if they differ from what's shown here):
```json
{
  "week_of": "2026-08-03",
  "poll_id": "6307421355511907907",
  "poll_message_id": 11,
  "poll_chat_id": -4254631451,
  "poll_posted_at": "2026-08-03T16:52:05.253506+00:00",
  "last_update_id": 278446642,
  "vote_counts": {"saturday": 2, "sunday": 6},
  "triggered": {"saturday": false, "sunday": true},
  "confirmed": {"saturday": false, "sunday": false},
  "posted_message_ids": {
    "saturday": [],
    "sunday": [202741, 202697, 202672, 202649, 202588, 202529, 202528, 202476, 202467, 202465, 202441, 202371, 202290, 202262, 202240, 202235, 202208, 202139, 202052, 202039, 201981, 201969, 201940, 202772, 202766, 203186, 203155, 203151, 203143, 203129, 203056, 203036, 202990, 202972, 202971, 202953, 202856, 202836, 202826, 202774, 203259, 203252, 203249, 203242, 203313, 203365, 203364, 203356]
  }
}
```

- [ ] **Step 4: Write the file, commit, and push**
```bash
cd "C:\Users\Yao Wei\badminton-bot"
git add state.json
git commit -m "chore: migrate state.json to day-keyed posted_message_ids + confirmed flag"
git push
```

- [ ] **Step 5: Trigger the watcher once and confirm it runs successfully against the migrated file** (manual `workflow_dispatch` run, check the run succeeds and `state.json` after the run still matches the expected shape) before considering this task done.

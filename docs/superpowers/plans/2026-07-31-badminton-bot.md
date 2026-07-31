# Badminton Court Auto-Matcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a $0, GitHub-Actions-driven Telegram bot that polls a friends' group for Saturday/Sunday badminton availability, and once a day hits a vote threshold, auto-posts matching "letting go" court listings from a separate group into the friends' group.

**Architecture:** Two Telegram actors (a Bot API bot in the friends' group, a Telethon userbot in the listings group) driven by two GitHub Actions cron workflows (`post-poll.yml`, `watch-and-match.yml`) that run stateless Python scripts and commit state back to `state.json` in the repo. A staging pair of throwaway Telegram groups is used for UAT before the real groups are ever touched.

**Tech Stack:** Python 3.11, `requests` (Telegram Bot API HTTP calls), `telethon` (MTProto userbot), `python-dateutil` (date fallback parsing), `pytest` (tests), GitHub Actions (scheduling).

**Spec:** [docs/superpowers/specs/2026-07-31-badminton-bot-design.md](../specs/2026-07-31-badminton-bot-design.md)

## Global Constraints

- Budget is $0 — GitHub Actions free tier, Telegram Bot API, Telethon only. No paid services, no external DB.
- No manual review step: matches auto-post immediately once found.
- `state.json` is the only persistence, committed back to the repo by the workflow at the end of each run.
- Poll is non-anonymous, single-answer, options in this exact order: `Saturday`, `Sunday`, `Both`, `Can't make it`.
- Vote threshold defaults to `4`, overridable via `VOTE_THRESHOLD` env/secret (used to lower it for staging UAT).
- Dedup is per-message, globally for the week — a listing posted once is never reposted that week.
- "This week's listing" = any listings-group message with timestamp `>= poll_posted_at`. No calendar-date matching.
- No edit/delete tracking on posted listings; no custom alerting beyond GitHub Actions' default failure emails.
- Real `FRIENDS_GROUP_CHAT_ID` / `LISTINGS_GROUP_CHAT_ID` are never used until the UAT checklist (Task 10) passes against staging groups.

---

## Repo Setup

This is a **new standalone repo**, separate from `claude.code`. All paths below are relative to the new repo's root, e.g. `C:\Users\Yao Wei\badminton-bot\`.

**Creating the GitHub repo and the first push are real, visible actions — confirm with the user before running `gh repo create` or `git push` for the first time in Task 1.**

Final file layout:

```
badminton-bot/
├── .github/workflows/
│   ├── post-poll.yml
│   └── watch-and-match.yml
├── src/
│   ├── __init__.py
│   ├── config.py           # env var loading (Task 1)
│   ├── state.py             # state.json schema + helpers (Task 2)
│   ├── parser.py            # supply/demand + day classification (Task 3)
│   ├── telegram_bot.py      # Bot API HTTP wrapper (Task 4)
│   ├── listings_client.py   # Telethon userbot wrapper (Task 5)
│   ├── poll.py               # Thursday poll-posting script (Task 6)
│   └── watcher.py            # vote-check -> match -> post script (Task 7)
├── tests/
│   ├── fixtures/
│   │   └── sample_messages.py
│   ├── test_config.py
│   ├── test_state.py
│   ├── test_parser.py
│   ├── test_telegram_bot.py
│   ├── test_listings_client.py
│   ├── test_poll.py
│   └── test_watcher.py
├── requirements.txt
├── requirements-dev.txt
├── .gitignore
└── README.md
```

`telegram_bot.py` and `listings_client.py` aren't in the design doc's original suggested tree — they're added here so `poll.py` and `watcher.py` (both of which need Bot API calls) share one implementation instead of duplicating HTTP/Telethon code (DRY).

---

### Task 1: Repo scaffolding + config module

**Files:**
- Create: `requirements.txt`
- Create: `requirements-dev.txt`
- Create: `.gitignore`
- Create: `src/__init__.py`
- Create: `src/config.py`
- Test: `tests/test_config.py`

**Interfaces:**
- Produces: `config.Config` dataclass with fields `bot_token: str`, `friends_chat_id: int`, `listings_chat_id: int`, `api_id: int`, `api_hash: str`, `userbot_session: str`, `vote_threshold: int`, `state_path: str`. `config.load_config() -> Config`, raises `ValueError` if a required env var is missing.

- [ ] **Step 1: Create the GitHub repo and local scaffolding**

Confirm with the user first, then:

```bash
mkdir "C:\Users\Yao Wei\badminton-bot"
cd "C:\Users\Yao Wei\badminton-bot"
git init
gh repo create badminton-bot --private --source=. --remote=origin
```

- [ ] **Step 2: Add `.gitignore`, `requirements.txt`, `requirements-dev.txt`**

`.gitignore`:
```
__pycache__/
*.pyc
.pytest_cache/
.venv/
```

`requirements.txt`:
```
requests>=2.31
telethon>=1.36
python-dateutil>=2.9
```

`requirements-dev.txt`:
```
-r requirements.txt
pytest>=8.0
```

- [ ] **Step 3: Create `src/__init__.py` (empty) and write the failing test for config**

`tests/test_config.py`:
```python
import pytest

from src import config

REQUIRED_ENV = {
    "TELEGRAM_BOT_TOKEN": "test-token",
    "FRIENDS_GROUP_CHAT_ID": "-100111",
    "LISTINGS_GROUP_CHAT_ID": "-100222",
    "TELEGRAM_API_ID": "12345",
    "TELEGRAM_API_HASH": "test-hash",
    "TELEGRAM_USERBOT_SESSION": "test-session",
}


def _set_required_env(monkeypatch):
    for key, value in REQUIRED_ENV.items():
        monkeypatch.setenv(key, value)


def test_load_config_reads_required_vars(monkeypatch):
    _set_required_env(monkeypatch)

    cfg = config.load_config()

    assert cfg.bot_token == "test-token"
    assert cfg.friends_chat_id == -100111
    assert cfg.listings_chat_id == -100222
    assert cfg.api_id == 12345
    assert cfg.api_hash == "test-hash"
    assert cfg.userbot_session == "test-session"


def test_load_config_defaults_vote_threshold_and_state_path(monkeypatch):
    _set_required_env(monkeypatch)
    monkeypatch.delenv("VOTE_THRESHOLD", raising=False)
    monkeypatch.delenv("STATE_PATH", raising=False)

    cfg = config.load_config()

    assert cfg.vote_threshold == 4
    assert cfg.state_path == "state.json"


def test_load_config_overrides_vote_threshold_and_state_path(monkeypatch):
    _set_required_env(monkeypatch)
    monkeypatch.setenv("VOTE_THRESHOLD", "1")
    monkeypatch.setenv("STATE_PATH", "staging_state.json")

    cfg = config.load_config()

    assert cfg.vote_threshold == 1
    assert cfg.state_path == "staging_state.json"


def test_load_config_raises_on_missing_required_var(monkeypatch):
    _set_required_env(monkeypatch)
    monkeypatch.delenv("TELEGRAM_BOT_TOKEN", raising=False)

    with pytest.raises(ValueError, match="TELEGRAM_BOT_TOKEN"):
        config.load_config()
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `pip install -r requirements-dev.txt && pytest tests/test_config.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'src.config'`

- [ ] **Step 5: Implement `src/config.py`**

```python
import os
from dataclasses import dataclass


@dataclass
class Config:
    bot_token: str
    friends_chat_id: int
    listings_chat_id: int
    api_id: int
    api_hash: str
    userbot_session: str
    vote_threshold: int
    state_path: str


def _require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ValueError(f"missing required environment variable: {name}")
    return value


def load_config() -> Config:
    return Config(
        bot_token=_require("TELEGRAM_BOT_TOKEN"),
        friends_chat_id=int(_require("FRIENDS_GROUP_CHAT_ID")),
        listings_chat_id=int(_require("LISTINGS_GROUP_CHAT_ID")),
        api_id=int(_require("TELEGRAM_API_ID")),
        api_hash=_require("TELEGRAM_API_HASH"),
        userbot_session=_require("TELEGRAM_USERBOT_SESSION"),
        vote_threshold=int(os.environ.get("VOTE_THRESHOLD", "4")),
        state_path=os.environ.get("STATE_PATH", "state.json"),
    )
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `pytest tests/test_config.py -v`
Expected: PASS (4 passed)

- [ ] **Step 7: Commit**

```bash
git add .gitignore requirements.txt requirements-dev.txt src/__init__.py src/config.py tests/test_config.py
git commit -m "feat: add repo scaffolding and config loading"
```

---

### Task 2: State management

**Files:**
- Create: `src/state.py`
- Test: `tests/test_state.py`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `state.load_state(path: str) -> dict`, `state.save_state(state: dict, path: str) -> None`, `state.new_week_state(poll_id: str, poll_message_id: int, poll_chat_id: int, poll_posted_at: str, week_of: str) -> dict`, `state.has_active_poll(state: dict) -> bool`, `state.is_triggered(state: dict, day: str) -> bool`, `state.mark_triggered(state: dict, day: str) -> None`, `state.is_posted(state: dict, message_id: int) -> bool`, `state.mark_posted(state: dict, message_id: int) -> None`. State dict shape:
```python
{
  "week_of": str | None,
  "poll_id": str | None,
  "poll_message_id": int | None,
  "poll_chat_id": int | None,
  "poll_posted_at": str | None,
  "last_update_id": int,
  "vote_counts": {"saturday": int, "sunday": int},
  "triggered": {"saturday": bool, "sunday": bool},
  "posted_message_ids": list[int],
}
```

- [ ] **Step 1: Write the failing tests**

`tests/test_state.py`:
```python
import json

from src import state


def test_load_state_missing_file_returns_default(tmp_path):
    path = str(tmp_path / "state.json")

    result = state.load_state(path)

    assert result["poll_id"] is None
    assert result["vote_counts"] == {"saturday": 0, "sunday": 0}
    assert result["triggered"] == {"saturday": False, "sunday": False}
    assert result["posted_message_ids"] == []


def test_default_state_independent_between_calls(tmp_path):
    path = str(tmp_path / "state.json")

    first = state.load_state(path)
    first["posted_message_ids"].append(999)
    first["triggered"]["saturday"] = True

    second = state.load_state(path)

    assert second["posted_message_ids"] == []
    assert second["triggered"]["saturday"] is False


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
    assert result["posted_message_ids"] == []


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


def test_mark_posted_and_is_posted_dedup():
    st = state.new_week_state("poll-1", 1234, -100999, "2026-07-30T01:00:00Z", "2026-08-01")

    assert state.is_posted(st, 555) is False

    state.mark_posted(st, 555)

    assert state.is_posted(st, 555) is True
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/test_state.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'src.state'`

- [ ] **Step 3: Implement `src/state.py`**

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
    "posted_message_ids": [],
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


def is_posted(state: dict, message_id: int) -> bool:
    return message_id in state["posted_message_ids"]


def mark_posted(state: dict, message_id: int) -> None:
    state["posted_message_ids"].append(message_id)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/test_state.py -v`
Expected: PASS (7 passed)

- [ ] **Step 5: Commit**

```bash
git add src/state.py tests/test_state.py
git commit -m "feat: add state.json load/save and trigger/dedup helpers"
```

---

### Task 3: Listing parser

**Files:**
- Create: `src/parser.py`
- Create: `tests/fixtures/sample_messages.py`
- Test: `tests/test_parser.py`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `parser.classify(text: str) -> str` (one of `"SUPPLY"`, `"DEMAND"`, `"UNKNOWN"`), `parser.extract_day(text: str) -> str | None` (lowercase day name or `None`), `parser.parse_listing(text: str) -> dict | None` (`{"day": str, "raw_text": str}` or `None`).

- [ ] **Step 1: Add the sample-message fixtures**

`tests/fixtures/sample_messages.py`:
```python
SUPPLY_SATURDAY = """Letting go court at cost

23 May (Saturday)
Jurong West Sports Hall
1-2PM

PM if interested"""

SUPPLY_SUNDAY = """Hi, 

Letting go court at cost $7.40

24 May ( Sunday ) 
3pm - 4pm 
Jurong West sport hall

Please PM if interested. 
Thanks"""

DEMAND_NO_DAY_NAME = """LF court in the east/ central on 23 May 7pm onwards
Pm if available thank you!"""

SUPPLY_NUMERIC_DATE_ONLY = """Letting go of court at cost, PM me
Date: 31 May 2026
Time: 6-8pm
Location: OTH
Price: $14"""

DEMAND_DOUBLE_SPACE = """looking  for court
Date: 24 May 2026 (sun)
Time: 11am - 1pm
Venue: riverside sec
pm of avaliable"""
```

- [ ] **Step 2: Write the failing tests**

`tests/test_parser.py`:
```python
from src import parser
from tests.fixtures import sample_messages as fx


def test_classify_supply_message():
    assert parser.classify(fx.SUPPLY_SATURDAY) == "SUPPLY"


def test_classify_demand_message_no_day_name():
    assert parser.classify(fx.DEMAND_NO_DAY_NAME) == "DEMAND"


def test_classify_demand_message_with_double_space():
    assert parser.classify(fx.DEMAND_DOUBLE_SPACE) == "DEMAND"


def test_classify_unknown_message():
    assert parser.classify("hey anyone free this weekend to play?") == "UNKNOWN"


def test_extract_day_from_day_name():
    assert parser.extract_day(fx.SUPPLY_SATURDAY) == "saturday"
    assert parser.extract_day(fx.SUPPLY_SUNDAY) == "sunday"


def test_extract_day_falls_back_to_numeric_date():
    assert parser.extract_day(fx.SUPPLY_NUMERIC_DATE_ONLY) == "sunday"


def test_extract_day_returns_none_when_no_day_found():
    assert parser.extract_day("letting go of a court, PM me for details") is None


def test_parse_listing_supply_saturday():
    assert parser.parse_listing(fx.SUPPLY_SATURDAY) == {
        "day": "saturday",
        "raw_text": fx.SUPPLY_SATURDAY,
    }


def test_parse_listing_supply_numeric_date_fallback():
    assert parser.parse_listing(fx.SUPPLY_NUMERIC_DATE_ONLY) == {
        "day": "sunday",
        "raw_text": fx.SUPPLY_NUMERIC_DATE_ONLY,
    }


def test_parse_listing_excludes_demand_messages():
    assert parser.parse_listing(fx.DEMAND_NO_DAY_NAME) is None
    assert parser.parse_listing(fx.DEMAND_DOUBLE_SPACE) is None
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `pytest tests/test_parser.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'src.parser'`

- [ ] **Step 4: Implement `src/parser.py`**

```python
import re

from dateutil import parser as dateutil_parser

SUPPLY_RE = re.compile(r"\b(letting go|let go|to let go)\b", re.IGNORECASE)
DEMAND_RE = re.compile(r"\b(looking\s+for|lf)\b", re.IGNORECASE)

DAY_NAME_RE = re.compile(
    r"\b(mon(?:day)?|tue(?:s|sday)?|wed(?:nesday)?|thu(?:rs|rsday)?"
    r"|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\b",
    re.IGNORECASE,
)
DAY_NAME_MAP = {
    "mon": "monday", "monday": "monday",
    "tue": "tuesday", "tues": "tuesday", "tuesday": "tuesday",
    "wed": "wednesday", "wednesday": "wednesday",
    "thu": "thursday", "thurs": "thursday", "thursday": "thursday",
    "fri": "friday", "friday": "friday",
    "sat": "saturday", "saturday": "saturday",
    "sun": "sunday", "sunday": "sunday",
}

# "DD Month YYYY" fallback only — bare numeric dates (e.g. "20/5") aren't
# matched in v1, no fixture requires it.
DATE_TEXTUAL_RE = re.compile(
    r"\b\d{1,2}\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may"
    r"|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?"
    r"|nov(?:ember)?|dec(?:ember)?)\s+\d{4}\b",
    re.IGNORECASE,
)


def classify(text: str) -> str:
    is_supply = bool(SUPPLY_RE.search(text))
    is_demand = bool(DEMAND_RE.search(text))
    if is_supply and not is_demand:
        return "SUPPLY"
    if is_demand:
        return "DEMAND"
    return "UNKNOWN"


def extract_day(text: str) -> str | None:
    name_match = DAY_NAME_RE.search(text)
    if name_match:
        return DAY_NAME_MAP[name_match.group(1).lower()]

    date_match = DATE_TEXTUAL_RE.search(text)
    if not date_match:
        return None
    try:
        parsed = dateutil_parser.parse(date_match.group(0), dayfirst=True)
    except (ValueError, OverflowError):
        return None
    return parsed.strftime("%A").lower()


def parse_listing(text: str) -> dict | None:
    if classify(text) != "SUPPLY":
        return None
    day = extract_day(text)
    if day not in ("saturday", "sunday"):
        return None
    return {"day": day, "raw_text": text}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `pytest tests/test_parser.py -v`
Expected: PASS (11 passed)

- [ ] **Step 6: Commit**

```bash
git add src/parser.py tests/fixtures/sample_messages.py tests/test_parser.py
git commit -m "feat: add supply/demand classifier and day extraction"
```

---

### Task 4: Telegram Bot API wrapper

**Files:**
- Create: `src/telegram_bot.py`
- Test: `tests/test_telegram_bot.py`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `telegram_bot.send_poll(token: str, chat_id: int, question: str, options: list[str]) -> dict` (returns the sent Message), `telegram_bot.get_updates(token: str, offset: int) -> list[dict]`, `telegram_bot.send_message(token: str, chat_id: int, text: str) -> dict`.

- [ ] **Step 1: Write the failing tests**

`tests/test_telegram_bot.py`:
```python
from unittest.mock import MagicMock, patch

import pytest

from src import telegram_bot


def _fake_response(payload):
    response = MagicMock()
    response.raise_for_status = MagicMock()
    response.json.return_value = payload
    return response


def test_send_poll_posts_correct_payload_and_returns_result():
    fake_result = {"message_id": 1234, "poll": {"id": "poll-1"}}
    with patch("src.telegram_bot.requests.post") as mock_post:
        mock_post.return_value = _fake_response({"ok": True, "result": fake_result})

        result = telegram_bot.send_poll(
            "tok", -100111, "Badminton?", ["Saturday", "Sunday", "Both", "Can't make it"]
        )

    assert result == fake_result
    url, kwargs = mock_post.call_args
    assert url[0] == "https://api.telegram.org/bottok/sendPoll"
    assert kwargs["json"]["chat_id"] == -100111
    assert kwargs["json"]["is_anonymous"] is False
    assert kwargs["json"]["allows_multiple_answers"] is False


def test_get_updates_returns_result_list():
    with patch("src.telegram_bot.requests.post") as mock_post:
        mock_post.return_value = _fake_response({"ok": True, "result": [{"update_id": 5}]})

        result = telegram_bot.get_updates("tok", 5)

    assert result == [{"update_id": 5}]


def test_send_message_returns_result():
    with patch("src.telegram_bot.requests.post") as mock_post:
        mock_post.return_value = _fake_response({"ok": True, "result": {"message_id": 42}})

        result = telegram_bot.send_message("tok", -100111, "hello")

    assert result == {"message_id": 42}


def test_call_raises_on_telegram_error_payload():
    with patch("src.telegram_bot.requests.post") as mock_post:
        mock_post.return_value = _fake_response({"ok": False, "description": "bad request"})

        with pytest.raises(RuntimeError, match="bad request"):
            telegram_bot.send_message("tok", -100111, "hello")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pytest tests/test_telegram_bot.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'src.telegram_bot'`

- [ ] **Step 3: Implement `src/telegram_bot.py`**

```python
import requests

API_URL_TEMPLATE = "https://api.telegram.org/bot{token}/{method}"


def _call(token: str, method: str, **params) -> dict:
    url = API_URL_TEMPLATE.format(token=token, method=method)
    response = requests.post(url, json=params, timeout=30)
    response.raise_for_status()
    payload = response.json()
    if not payload.get("ok"):
        raise RuntimeError(f"Telegram API error calling {method}: {payload}")
    return payload["result"]


def send_poll(token: str, chat_id: int, question: str, options: list[str]) -> dict:
    return _call(
        token,
        "sendPoll",
        chat_id=chat_id,
        question=question,
        options=options,
        is_anonymous=False,
        allows_multiple_answers=False,
    )


def get_updates(token: str, offset: int) -> list[dict]:
    return _call(token, "getUpdates", offset=offset, timeout=0)


def send_message(token: str, chat_id: int, text: str) -> dict:
    return _call(token, "sendMessage", chat_id=chat_id, text=text)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/test_telegram_bot.py -v`
Expected: PASS (4 passed)

- [ ] **Step 5: Commit**

```bash
git add src/telegram_bot.py tests/test_telegram_bot.py
git commit -m "feat: add Telegram Bot API wrapper"
```

---

### Task 5: Listings userbot client

**Files:**
- Create: `src/listings_client.py`
- Test: `tests/test_listings_client.py`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `listings_client.fetch_messages_since(api_id: int, api_hash: str, session_string: str, chat_id: int, since: datetime) -> list[dict]`, each item `{"id": int, "text": str, "date": datetime}`.

- [ ] **Step 1: Write the failing test**

`tests/test_listings_client.py`:
```python
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

from src import listings_client


def test_fetch_messages_since_stops_before_cutoff_and_skips_empty_text():
    since = datetime(2026, 7, 30, 1, 0, tzinfo=timezone.utc)
    newest = MagicMock(id=3, text="new listing", date=datetime(2026, 7, 30, 5, 0, tzinfo=timezone.utc))
    no_text = MagicMock(id=2, text=None, date=datetime(2026, 7, 30, 4, 0, tzinfo=timezone.utc))
    older = MagicMock(id=1, text="old listing", date=datetime(2026, 7, 29, 5, 0, tzinfo=timezone.utc))

    async def fake_iter_messages(chat_id):
        for message in (newest, no_text, older):
            yield message

    fake_client = MagicMock()
    fake_client.connect = AsyncMock()
    fake_client.disconnect = AsyncMock()
    fake_client.iter_messages = fake_iter_messages

    with patch("src.listings_client.TelegramClient", return_value=fake_client):
        result = listings_client.fetch_messages_since(111, "hash", "session", -100222, since)

    assert result == [{"id": 3, "text": "new listing", "date": newest.date}]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pytest tests/test_listings_client.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'src.listings_client'`

- [ ] **Step 3: Implement `src/listings_client.py`**

```python
import asyncio
from datetime import datetime

from telethon import TelegramClient
from telethon.sessions import StringSession


async def _fetch(
    api_id: int, api_hash: str, session_string: str, chat_id: int, since: datetime
) -> list[dict]:
    client = TelegramClient(StringSession(session_string), api_id, api_hash)
    await client.connect()
    try:
        messages = []
        async for message in client.iter_messages(chat_id):
            if message.date is None or message.date < since:
                break
            if not message.text:
                continue
            messages.append({"id": message.id, "text": message.text, "date": message.date})
        return messages
    finally:
        await client.disconnect()


def fetch_messages_since(
    api_id: int, api_hash: str, session_string: str, chat_id: int, since: datetime
) -> list[dict]:
    return asyncio.run(_fetch(api_id, api_hash, session_string, chat_id, since))
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pytest tests/test_listings_client.py -v`
Expected: PASS (1 passed)

- [ ] **Step 5: Commit**

```bash
git add src/listings_client.py tests/test_listings_client.py
git commit -m "feat: add Telethon userbot client for listings group"
```

---

### Task 6: Poll-posting script

**Files:**
- Create: `src/poll.py`
- Test: `tests/test_poll.py`

**Interfaces:**
- Consumes: `config.load_config()`, `telegram_bot.send_poll(...)`, `state.new_week_state(...)`, `state.save_state(...)`.
- Produces: `poll.POLL_QUESTION: str`, `poll.POLL_OPTIONS: list[str]`, `poll.main() -> None`.

- [ ] **Step 1: Write the failing test**

`tests/test_poll.py`:
```python
from unittest.mock import MagicMock, patch

from src import poll
from src.config import Config


def _fake_config():
    return Config(
        bot_token="tok",
        friends_chat_id=-100111,
        listings_chat_id=-100222,
        api_id=1,
        api_hash="hash",
        userbot_session="session",
        vote_threshold=4,
        state_path="state.json",
    )


def test_main_posts_poll_and_saves_new_week_state():
    fake_poll_result = {"message_id": 999, "poll": {"id": "poll-abc"}}

    with (
        patch("src.poll.config.load_config", return_value=_fake_config()),
        patch("src.poll.telegram_bot.send_poll", return_value=fake_poll_result) as mock_send,
        patch("src.poll.state.save_state") as mock_save,
    ):
        poll.main()

    mock_send.assert_called_once_with(
        "tok", -100111, poll.POLL_QUESTION, poll.POLL_OPTIONS
    )
    saved_state, saved_path = mock_save.call_args[0]
    assert saved_state["poll_id"] == "poll-abc"
    assert saved_state["poll_message_id"] == 999
    assert saved_state["poll_chat_id"] == -100111
    assert saved_path == "state.json"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pytest tests/test_poll.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'src.poll'`

- [ ] **Step 3: Implement `src/poll.py`**

```python
from datetime import datetime, timezone

from src import config, state, telegram_bot

POLL_QUESTION = "Badminton this weekend?"
POLL_OPTIONS = ["Saturday", "Sunday", "Both", "Can't make it"]


def main() -> None:
    cfg = config.load_config()
    now = datetime.now(timezone.utc)

    result = telegram_bot.send_poll(cfg.bot_token, cfg.friends_chat_id, POLL_QUESTION, POLL_OPTIONS)

    new_state = state.new_week_state(
        poll_id=result["poll"]["id"],
        poll_message_id=result["message_id"],
        poll_chat_id=cfg.friends_chat_id,
        poll_posted_at=now.isoformat(),
        week_of=now.date().isoformat(),
    )
    state.save_state(new_state, cfg.state_path)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `pytest tests/test_poll.py -v`
Expected: PASS (1 passed)

- [ ] **Step 5: Commit**

```bash
git add src/poll.py tests/test_poll.py
git commit -m "feat: add weekly poll-posting script"
```

---

### Task 7: Watcher script

**Files:**
- Create: `src/watcher.py`
- Test: `tests/test_watcher.py`

**Interfaces:**
- Consumes: `config.load_config()`, `state.load_state/save_state/has_active_poll/is_triggered/mark_triggered/is_posted/mark_posted`, `telegram_bot.get_updates/send_message`, `listings_client.fetch_messages_since`, `parser.parse_listing`.
- Produces: `watcher.in_watch_window(now_sgt: datetime) -> bool`, `watcher.extract_vote_counts(poll_options: list[dict]) -> dict`, `watcher.main() -> None`.

- [ ] **Step 1: Write the failing tests**

`tests/test_watcher.py`:
```python
from datetime import datetime, timezone
from unittest.mock import patch

from src import watcher
from src.config import Config


def _fake_config(vote_threshold=4):
    return Config(
        bot_token="tok",
        friends_chat_id=-100111,
        listings_chat_id=-100222,
        api_id=1,
        api_hash="hash",
        userbot_session="session",
        vote_threshold=vote_threshold,
        state_path="state.json",
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
        "posted_message_ids": [],
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
        {"id": 501, "text": "Letting go court, Saturday 3pm, PM me", "date": None},
        {"id": 502, "text": "LF court Saturday, PM me", "date": None},
    ]

    with (
        patch("src.watcher.config.load_config", return_value=_fake_config()),
        patch("src.watcher.datetime") as mock_datetime,
        patch("src.watcher.state.load_state", return_value=st),
        patch("src.watcher.telegram_bot.get_updates", return_value=updates),
        patch("src.watcher.listings_client.fetch_messages_since", return_value=listings),
        patch("src.watcher.telegram_bot.send_message") as mock_send_message,
        patch("src.watcher.state.save_state") as mock_save_state,
    ):
        mock_datetime.now.return_value = datetime(2026, 8, 1, 14, 0, tzinfo=watcher.SGT)
        mock_datetime.fromisoformat.side_effect = datetime.fromisoformat
        watcher.main()

    mock_send_message.assert_called_once()
    call_args = mock_send_message.call_args[0]
    assert call_args[0] == "tok"
    assert call_args[1] == -100111
    assert "Letting go court, Saturday 3pm, PM me" in call_args[2]
    saved_state = mock_save_state.call_args[0][0]
    assert saved_state["triggered"]["saturday"] is True
    assert saved_state["posted_message_ids"] == [501]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pytest tests/test_watcher.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'src.watcher'`

- [ ] **Step 3: Implement `src/watcher.py`**

```python
from datetime import datetime, timedelta, timezone

from src import config, listings_client, parser, state, telegram_bot

SGT = timezone(timedelta(hours=8))


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


def _update_vote_counts(cfg: config.Config, st: dict) -> None:
    updates = telegram_bot.get_updates(cfg.bot_token, st["last_update_id"] + 1)
    for update in updates:
        st["last_update_id"] = max(st["last_update_id"], update["update_id"])
        poll = update.get("poll")
        if not poll or poll["id"] != st["poll_id"]:
            continue
        st["vote_counts"] = extract_vote_counts(poll["options"])


def _process_day(cfg: config.Config, st: dict, day: str) -> None:
    if state.is_triggered(st, day):
        return
    if st["vote_counts"][day] < cfg.vote_threshold:
        return

    state.mark_triggered(st, day)
    since = datetime.fromisoformat(st["poll_posted_at"])
    messages = listings_client.fetch_messages_since(
        cfg.api_id, cfg.api_hash, cfg.userbot_session, cfg.listings_chat_id, since
    )
    for message in messages:
        listing = parser.parse_listing(message["text"])
        if listing is None or listing["day"] != day:
            continue
        if state.is_posted(st, message["id"]):
            continue
        text = f"\U0001f3f8 Match for {day.capitalize()}:\n\n{listing['raw_text']}"
        telegram_bot.send_message(cfg.bot_token, cfg.friends_chat_id, text)
        state.mark_posted(st, message["id"])


def main() -> None:
    cfg = config.load_config()
    now_sgt = datetime.now(SGT)
    if not in_watch_window(now_sgt):
        return

    st = state.load_state(cfg.state_path)
    if not state.has_active_poll(st):
        return

    _update_vote_counts(cfg, st)
    _process_day(cfg, st, "saturday")
    _process_day(cfg, st, "sunday")
    state.save_state(st, cfg.state_path)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pytest tests/test_watcher.py -v`
Expected: PASS (7 passed)

- [ ] **Step 5: Run the full test suite**

Run: `pytest -v`
Expected: PASS (all tests across every module)

- [ ] **Step 6: Commit**

```bash
git add src/watcher.py tests/test_watcher.py
git commit -m "feat: add watcher script tying vote-checking to match-posting"
```

---

### Task 8: GitHub Actions workflows

**Files:**
- Create: `.github/workflows/post-poll.yml`
- Create: `.github/workflows/watch-and-match.yml`

**Interfaces:**
- Consumes: `src/poll.py`, `src/watcher.py`, `requirements.txt`, and all secrets listed in Global Constraints.
- Produces: two scheduled workflows that run the scripts and commit `state.json` back to the repo.

- [ ] **Step 1: Write `.github/workflows/post-poll.yml`**

```yaml
name: Post weekly poll

on:
  schedule:
    - cron: "0 1 * * 4"
  workflow_dispatch: {}

permissions:
  contents: write

jobs:
  post-poll:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - run: pip install -r requirements.txt

      - run: python -m src.poll
        env:
          TELEGRAM_BOT_TOKEN: ${{ secrets.TELEGRAM_BOT_TOKEN }}
          FRIENDS_GROUP_CHAT_ID: ${{ secrets.FRIENDS_GROUP_CHAT_ID }}
          LISTINGS_GROUP_CHAT_ID: ${{ secrets.LISTINGS_GROUP_CHAT_ID }}
          TELEGRAM_API_ID: ${{ secrets.TELEGRAM_API_ID }}
          TELEGRAM_API_HASH: ${{ secrets.TELEGRAM_API_HASH }}
          TELEGRAM_USERBOT_SESSION: ${{ secrets.TELEGRAM_USERBOT_SESSION }}
          VOTE_THRESHOLD: ${{ secrets.VOTE_THRESHOLD }}

      - name: Commit updated state.json
        run: |
          git config user.name "badminton-bot"
          git config user.email "actions@users.noreply.github.com"
          git add state.json
          git diff --cached --quiet || git commit -m "chore: update state.json (post-poll)"
          git pull --rebase
          git push
```

- [ ] **Step 2: Write `.github/workflows/watch-and-match.yml`**

```yaml
name: Watch votes and post matches

on:
  schedule:
    - cron: "*/15 * * * *"
  workflow_dispatch: {}

permissions:
  contents: write

jobs:
  watch-and-match:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - run: pip install -r requirements.txt

      - run: python -m src.watcher
        env:
          TELEGRAM_BOT_TOKEN: ${{ secrets.TELEGRAM_BOT_TOKEN }}
          FRIENDS_GROUP_CHAT_ID: ${{ secrets.FRIENDS_GROUP_CHAT_ID }}
          LISTINGS_GROUP_CHAT_ID: ${{ secrets.LISTINGS_GROUP_CHAT_ID }}
          TELEGRAM_API_ID: ${{ secrets.TELEGRAM_API_ID }}
          TELEGRAM_API_HASH: ${{ secrets.TELEGRAM_API_HASH }}
          TELEGRAM_USERBOT_SESSION: ${{ secrets.TELEGRAM_USERBOT_SESSION }}
          VOTE_THRESHOLD: ${{ secrets.VOTE_THRESHOLD }}

      - name: Commit updated state.json
        run: |
          git config user.name "badminton-bot"
          git config user.email "actions@users.noreply.github.com"
          git add state.json
          git diff --cached --quiet || git commit -m "chore: update state.json (watcher)"
          git pull --rebase
          git push
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/post-poll.yml .github/workflows/watch-and-match.yml
git commit -m "feat: add GitHub Actions cron workflows for poll and watcher"
```

---

### Task 9: README — setup, secrets, and staging groups

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: nothing (documentation only).
- Produces: a setup guide a future reader (including the user, months from now) can follow with zero prior context.

- [ ] **Step 1: Write `README.md`**

```markdown
# badminton-bot

Polls a Telegram friends' group for Saturday/Sunday badminton availability;
once 4 people confirm a day, auto-posts matching "letting go" court listings
from a separate listings group into the friends' group. $0 infra: GitHub
Actions + Telegram Bot API + Telethon.

Full design: `docs/superpowers/specs/2026-07-31-badminton-bot-design.md` in the
`claude.code` repo (a separate repo — not part of this one).

## One-time setup

1. **Create the bot**: message [@BotFather](https://t.me/BotFather), run
   `/newbot`, note the token it gives you — this is `TELEGRAM_BOT_TOKEN`.
2. **Add the bot to your friends' group** and send any message there. Then
   visit `https://api.telegram.org/bot<TOKEN>/getUpdates` in a browser and
   find `"chat":{"id":...}` for that group — this is `FRIENDS_GROUP_CHAT_ID`
   (a negative number for groups).
3. **Get the listings group's chat ID**: since the bot can't join it, use the
   one-time Telethon script in step 5 below — after logging in, run
   `client.get_dialogs()` and print `d.id, d.name` for each, find the
   listings group — this is `LISTINGS_GROUP_CHAT_ID`.
4. **Register at [my.telegram.org](https://my.telegram.org)** → API
   development tools → create an app. Note `api_id` (`TELEGRAM_API_ID`) and
   `api_hash` (`TELEGRAM_API_HASH`).
5. **Generate the userbot session string** locally (one-time, interactive):
   ```bash
   pip install telethon
   python -c "
   from telethon.sync import TelegramClient
   from telethon.sessions import StringSession
   api_id = int(input('api_id: '))
   api_hash = input('api_hash: ')
   with TelegramClient(StringSession(), api_id, api_hash) as client:
       print(client.session.save())
   "
   ```
   Log in with your own phone number when prompted. The printed string is
   `TELEGRAM_USERBOT_SESSION` — treat it like a password, it's a login
   session for your personal account.
6. **Set GitHub repo secrets** (Settings → Secrets and variables → Actions):
   `TELEGRAM_BOT_TOKEN`, `FRIENDS_GROUP_CHAT_ID`, `LISTINGS_GROUP_CHAT_ID`,
   `TELEGRAM_API_ID`, `TELEGRAM_API_HASH`, `TELEGRAM_USERBOT_SESSION`.

## Staging (UAT) before launch

Do not point the bot at your real groups yet.

1. Create two new, throwaway Telegram groups you control: a test "friends'"
   group and a test "listings" group. Add the bot to the test friends' group
   (same way as step 2 above). Your own account (the userbot) is already a
   member of anything you create.
2. Set `FRIENDS_GROUP_CHAT_ID` / `LISTINGS_GROUP_CHAT_ID` secrets to these
   test groups' chat IDs.
3. Add a `VOTE_THRESHOLD` secret set to `1` or `2` so you can trigger the
   match flow without needing 4 real voters.
4. Trigger `post-poll.yml` manually (Actions tab → Post weekly poll → Run
   workflow) and vote in the test group.
5. Post a hand-written test "letting go" message into the test listings
   group, matching the day you voted for.
6. Trigger `watch-and-match.yml` manually and confirm a match gets posted to
   the test friends' group.
7. Work through the full UAT checklist in the design spec before launching.

## Launch

Once UAT passes: edit `FRIENDS_GROUP_CHAT_ID` / `LISTINGS_GROUP_CHAT_ID` to
the real group IDs, and delete (or set to `4`) the `VOTE_THRESHOLD` secret.
That's the entire launch step — no code changes.

## Development

```bash
pip install -r requirements-dev.txt
pytest -v
```
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add setup, staging/UAT, and launch instructions"
```

---

### Task 10: Manual UAT pass and launch

This task has no code changes — it's the user manually exercising the system
end-to-end against staging groups, per the design spec's UAT acceptance
criteria, before flipping to production secrets.

**Files:** none (manual verification only).

- [ ] **Step 1: Follow README.md's "Staging (UAT) before launch" section** to create test groups, set staging secrets (`VOTE_THRESHOLD=1` or `2`), and manually trigger both workflows via `workflow_dispatch`.

- [ ] **Step 2: Work through each UAT acceptance criterion from the design spec**, confirming each one against the actual staging run:
  1. Poll posts on schedule with the correct 4 options.
  2. Watcher correctly tallies votes per day, including a "Both" vote counting toward both days.
  3. Trigger fires exactly once per day when the threshold is reached (does not re-fire on subsequent runs — trigger `watch-and-match.yml` a second time after criterion 3 already passed and confirm no duplicate post).
  4. A real-shaped SUPPLY listing posted after the poll, matching the triggered day, gets posted to the test friends' group.
  5. A DEMAND ("looking for") listing is correctly excluded.
  6. A listing already posted is not posted again on a later run, even if it also matches the other triggered day.
  7. A listing posted *before* the poll (predating `poll_posted_at`) is correctly excluded from matching.

- [ ] **Step 3: If any criterion fails**, fix the relevant module (with a new failing test reproducing the issue first, per TDD), commit, and re-run the affected UAT criteria — do not skip straight to launch on a partial pass.

- [ ] **Step 4: Launch** — once all 7 criteria pass, edit `FRIENDS_GROUP_CHAT_ID` / `LISTINGS_GROUP_CHAT_ID` GitHub secrets to the real group IDs, and delete (or set to `4`) the `VOTE_THRESHOLD` secret. Confirm with the user before this step, since it's the point where the bot starts posting into their real friends' group.

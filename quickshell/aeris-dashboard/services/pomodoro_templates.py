"""Declarative Obsidian routines; no scripts, arbitrary commands, or note writes."""
from contextlib import contextmanager
import fcntl
import json
import math
import os
from pathlib import Path
import random
import re
import tempfile
import time

import yaml

FIELDS = {"type", "id", "name", "work_minutes", "break_minutes", "long_break_minutes",
          "sessions", "auto_advance", "work_label", "short_break_labels", "long_break_label", "quotes"}
_cache = None
_cache_time = 0


def template_dir():
    override = os.environ.get("AERIS_TOMAT_TEMPLATE_DIR")
    if override:
        return Path(override)
    for config in (Path.home() / ".var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json",
                   Path.home() / ".config/obsidian/obsidian.json"):
        if not config.exists():
            continue
        data = json.loads(config.read_text())
        candidates = [v for v in data.get("vaults", {}).values()
                      if (Path(v.get("path", "")) / ".obsidian").is_dir()]
        if candidates:
            vault = max(candidates, key=lambda v: (bool(v.get("open")), v.get("ts", 0)))
            return Path(vault["path"]) / "Aeris/Pomodoro Templates"
    raise ValueError("No configured Obsidian vault found")


def text(value, field, limit):
    if not isinstance(value, str) or not value.strip() or len(value) > limit or any(ord(c) < 32 for c in value):
        raise ValueError(f"{field}: expected text of 1–{limit} characters")
    return value.strip()


def validate(data):
    if not isinstance(data, dict) or data.get("type") != "aeris-pomodoro":
        raise ValueError("type must be aeris-pomodoro")
    if set(data) - FIELDS:
        raise ValueError("Unknown fields: " + ", ".join(sorted(str(k) for k in set(data) - FIELDS)))
    result = {"id": text(data.get("id"), "id", 48), "name": text(data.get("name"), "name", 32)}
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", result["id"]):
        raise ValueError("id must be a lowercase slug")
    for field in ("work_minutes", "break_minutes", "long_break_minutes"):
        value = data.get(field)
        if type(value) not in (float, int) or not math.isfinite(value) or not 1 <= value <= 180:
            raise ValueError(f"{field}: expected 1–180 minutes")
        result[field] = value
    sessions = data.get("sessions", 4)
    if type(sessions) is not int or not 1 <= sessions <= 8:
        raise ValueError("sessions: expected 1–8")
    result["sessions"] = sessions
    advance = data.get("auto_advance", "none")
    if advance not in ("none", "all", "to-break", "to-work"):
        raise ValueError("auto_advance: none, all, to-break, or to-work")
    result["auto_advance"] = advance
    result["work_label"] = text(data.get("work_label", "WORK"), "work_label", 16)
    result["long_break_label"] = text(data.get("long_break_label", "LONG BREAK"), "long_break_label", 16)
    labels = data.get("short_break_labels", ["REST"])
    if not isinstance(labels, list) or not 1 <= len(labels) <= 8:
        raise ValueError("short_break_labels: expected 1–8 labels")
    result["short_break_labels"] = [text(v, "break label", 16) for v in labels]
    quotes = data.get("quotes", ["Nothing lasts. Make it count."])
    if not isinstance(quotes, list) or not 1 <= len(quotes) <= 32:
        raise ValueError("quotes: expected 1–32 original lines")
    result["quotes"] = [text(v, "quote", 72) for v in quotes]
    return result


def catalog(force=False):
    global _cache, _cache_time
    if not force and _cache is not None and time.monotonic() - _cache_time < 3:
        return _cache
    routines, errors, seen = [], [], set()
    try:
        directory = template_dir()
        if not directory.is_dir():
            raise ValueError(f"Template folder not found: {directory}")
        for path in sorted(directory.glob("*.md"))[:64]:
            if path.is_symlink():
                continue
            try:
                if path.stat().st_size > 65536:
                    raise ValueError("Template exceeds 64 KB")
                content = path.read_text(encoding="utf-8")
                match = re.match(r"\A---\s*\n(.*?)\n---(?:\s*\n|$)", content, re.S)
                if not match:
                    continue  # Guide notes need no routine frontmatter.
                raw = yaml.safe_load(match[1])
                routine = validate(raw)
                if routine["id"] in seen:
                    # Reject every duplicate, not whichever file happens to come second.
                    routines = [r for r in routines if r["id"] != routine["id"]]
                    raise ValueError(f"Duplicate routine id: {routine['id']}")
                seen.add(routine["id"])
                routines.append(routine)
            except (OSError, ValueError, yaml.YAMLError) as error:
                errors.append(f"{path.name}: {error}")
    except (OSError, ValueError) as error:
        errors.append(str(error))
    _cache = {"templates": routines, "templateErrors": errors}
    _cache_time = time.monotonic()
    return _cache


def state_path():
    override = os.environ.get("AERIS_TOMAT_STATE_DIR")
    base = Path(override) if override else Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "aeris-pomodoro"
    return base / "selection.json"


def load():
    path = state_path()
    if not path.exists():
        return {}
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError("Invalid saved routine selection")
    return data


def save(data):
    path = state_path()
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, staging = tempfile.mkstemp(dir=path.parent, prefix=".selection-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(staging, path)
    finally:
        if os.path.exists(staging):
            os.unlink(staging)


@contextmanager
def locked():
    path = state_path().with_suffix(".lock")
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def find(identifier, entries):
    result = next((r for r in entries if r["id"] == identifier), None)
    if result is None:
        raise ValueError("Selected routine is missing or invalid; choose another in the picker")
    return result


def selected(model, entries):
    if model.get("selected"):
        return find(model["selected"], entries)
    return next((r for r in entries if r["id"] == "classic"), entries[0] if entries else None)


def start(routine, model, request):
    request("start", {"work": routine["work_minutes"], "break": routine["break_minutes"],
                      "long_break": routine["long_break_minutes"], "sessions": routine["sessions"],
                      "auto_advance": routine["auto_advance"]})
    model.update(selected=routine["id"], active=routine, boot=boot_id(), startedAt=time.monotonic(),
                 quote=random.choice(routine["quotes"]))
    save(model)


def boot_id():
    return Path("/proc/sys/kernel/random/boot_id").read_text().strip()


def enrich(state, observed_at=None):
    observed_at = time.monotonic() if observed_at is None else observed_at
    data = catalog()
    errors = list(data["templateErrors"])
    try:
        model = load()
        if model.get("active") and (state["phase"] == "Idle" or model.get("boot") != boot_id()):
            with locked():
                model = load()
                # A stale Idle response must not erase a just-started snapshot.
                if model.get("boot") != boot_id() or model.get("startedAt", 0) < observed_at:
                    model.pop("active", None)
                    model.pop("quote", None)
                    save(model)
    except (OSError, ValueError) as error:
        model = {}
        errors.append(f"Saved selection: {error}")
    try:
        choice = selected(model, data["templates"])
    except ValueError as error:
        choice = None
        errors.append(str(error))
    active = model.get("active") if state["phase"] != "Idle" else None
    routine = active or (choice if state["phase"] == "Idle" else None)
    result = {**state, **data, "templateErrors": errors}
    result.update(selectedId=choice["id"] if choice else "", selectedName=choice["name"] if choice else "",
                  activeName=active["name"] if active else "", activeId=active["id"] if active else "",
                  quote=model.get("quote", "Nothing lasts. Make it count."))
    if routine:
        if state["phase"] == "Idle":
            result.update(remaining=round(routine["work_minutes"] * 60), duration=round(routine["work_minutes"] * 60),
                          sessions=routine["sessions"], session=1, progress=0, quote=routine["quotes"][0])
        phase = state["phase"]
        # Tomat increments current_session when entering the preceding short break.
        index = max(0, state["session"] - 2) % len(routine["short_break_labels"])
        result["stageLabel"] = (routine["short_break_labels"][index] if phase == "Break" else
                                routine["long_break_label"] if phase == "LongBreak" else routine["work_label"])
    return result


def action(name, raw_state, request, identifier=None, mode=None):
    # A broken note or saved selection must not prevent pausing/skipping a timer.
    if name in ("pause", "resume", "skip") or (name == "toggle" and raw_state["phase"] != "Idle"):
        request(name)
        return
    with locked():
        try:
            model = load()
        except ValueError:
            if name not in ("select", "reset"):
                raise
            # An explicit new selection/reset can recover invalid saved metadata.
            model = {}
        entries = catalog(force=True)["templates"]
        if name == "select":
            if mode not in ("next", "now"):
                raise ValueError("Choose next or now")
            routine = find(identifier, entries)
            if mode == "now" and raw_state["phase"] != "Idle":
                start(routine, model, request)
            else:
                model["selected"] = routine["id"]
                save(model)
        elif name == "toggle" and raw_state["phase"] == "Idle":
            routine = selected(model, entries)
            if routine is None:
                raise ValueError("No valid Obsidian routines. Open the template picker.")
            start(routine, model, request)
        else:
            request({"reset": "stop"}.get(name, name))
            if name == "reset":
                model.pop("active", None)
                model.pop("quote", None)
                save(model)

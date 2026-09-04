#!/usr/bin/env python3
"""Resolve browser media artwork when MPRIS omits it."""

import argparse
import json
import os
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path


CACHE_MAX_AGE = 30 * 24 * 60 * 60
VIDEO_ID_PATTERN = re.compile(r'"videoId":"([A-Za-z0-9_-]{11})"')


def cache_path():
    cache_root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    return cache_root / "aeris-dashboard" / "media-art.json"


def load_cache():
    try:
        data = json.loads(cache_path().read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError, TypeError):
        return {}


def save_cache(cache):
    path = cache_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(cache, separators=(",", ":")), encoding="utf-8")
    temporary.replace(path)


def normalized_key(title, artist):
    return " ".join(f"{artist} {title}".casefold().split())


def search_youtube(title, artist):
    query = " ".join(part for part in (artist.strip(), title.strip()) if part)
    url = "https://www.youtube.com/results?search_query=" + urllib.parse.quote_plus(query)
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=8) as response:
        page = response.read().decode("utf-8", "replace")
    match = VIDEO_ID_PATTERN.search(page)
    if not match:
        return ""
    return f"https://i.ytimg.com/vi/{match.group(1)}/hqdefault.jpg"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--title", required=True)
    parser.add_argument("--artist", default="")
    args = parser.parse_args()

    key = normalized_key(args.title, args.artist)
    if not key:
        print(json.dumps({"url": ""}))
        return 0

    now = int(time.time())
    cache = load_cache()
    cached = cache.get(key, {})
    if cached.get("url") and now - int(cached.get("updated", 0)) < CACHE_MAX_AGE:
        print(json.dumps({"url": cached["url"]}))
        return 0

    try:
        artwork_url = search_youtube(args.title, args.artist)
    except (OSError, TimeoutError):
        artwork_url = ""

    if artwork_url:
        cache[key] = {"url": artwork_url, "updated": now}
        try:
            save_cache(cache)
        except OSError:
            pass

    print(json.dumps({"url": artwork_url}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

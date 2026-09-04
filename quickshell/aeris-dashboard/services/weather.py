#!/usr/bin/python3
"""Open-Meteo current model conditions, with bounded, location-keyed disk cache."""
import argparse
import json
import math
import os
from pathlib import Path
import tempfile
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen

MAX_AGE = 6 * 3600
REFRESH = 600
ERRORS = (OSError, ValueError, KeyError, TypeError)


def location():
    path = Path(os.environ.get("AERIS_WEATHER_CONFIG", str(Path(os.environ.get(
        "XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "aeris-dashboard/weather.json")))
    data = json.loads(path.read_text())
    for field, limit in (("latitude", 90), ("longitude", 180)):
        value = data[field]
        if type(value) not in (int, float) or not math.isfinite(value) or abs(value) > limit:
            raise ValueError("Invalid weather coordinates")
    if not isinstance(data.get("name"), str) or not 1 <= len(data["name"]) <= 80:
        raise ValueError("Invalid weather location name")
    return {key: data[key] for key in ("name", "latitude", "longitude")}


def condition(code, day):
    if code in (0, 1):
        return ("Clear sky" if code == 0 else "Mainly clear", "clear" if day else "night",
                "white-balance-sunny" if day else "moon-waning-crescent")
    if code == 2:
        return ("Partly cloudy", "partly-cloudy", "weather-partly-cloudy" if day else "weather-night-partly-cloudy")
    if code == 3:
        return ("Overcast", "cloudy", "weather-cloudy")
    if code in (45, 48):
        return ("Fog", "fog", "weather-fog")
    if code in (51, 53, 55, 56, 57):
        return ("Freezing drizzle" if code in (56, 57) else "Drizzle", "rain", "weather-rainy")
    if code in (61, 63, 65, 66, 67, 80, 81, 82):
        label = "Freezing rain" if code in (66, 67) else "Showers" if code >= 80 else "Rain"
        return (label, "rain", "weather-rainy")
    if code in (71, 73, 75, 77, 85, 86):
        return ("Snow showers" if code >= 85 else "Snow", "snow", "weather-snowy")
    if code in (95, 96, 99):
        return ("Thunder + hail" if code in (96, 99) else "Thunderstorm", "storm", "weather-lightning-rainy")
    return ("Unknown conditions", "unknown", "weather-cloudy")


def normalize(data, now):
    current = data["current"]
    temperature = current["temperature_2m"]
    code, day, measured = current["weather_code"], current["is_day"], current["time"]
    if type(temperature) not in (int, float) or not math.isfinite(temperature) or not -100 <= temperature <= 70:
        raise ValueError("Invalid weather temperature")
    if type(code) is not int or type(day) is not int or day not in (0, 1):
        raise ValueError("Invalid weather condition")
    if type(measured) not in (int, float) or not math.isfinite(measured) or not -300 <= now - measured < MAX_AGE:
        raise ValueError("Weather provider returned an expired timestamp")
    if data["current_units"]["temperature_2m"] != "°C":
        raise ValueError("Unexpected weather temperature unit")
    label, pattern, icon = condition(code, day)
    return {"temperature": temperature, "code": code, "isDay": bool(day),
            "description": label, "condition": pattern, "icon": icon,
            "observedAt": measured, "fetchedAt": now}


def fetch(place, now):
    query = urlencode({"latitude": place["latitude"], "longitude": place["longitude"],
        "current": "temperature_2m,weather_code,is_day", "temperature_unit": "celsius",
        "timeformat": "unixtime", "timezone": "auto", "forecast_days": 1})
    req = Request("https://api.open-meteo.com/v1/forecast?" + query,
                  headers={"User-Agent": "Aeris-Weather/1.0"})
    with urlopen(req, timeout=12) as response:
        payload = response.read(131073)
    if len(payload) > 131072:
        raise ValueError("Weather response too large")
    return normalize(json.loads(payload), now)


def cache_path():
    return Path(os.environ.get("AERIS_WEATHER_CACHE", str(Path(os.environ.get(
        "XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "aeris-dashboard/weather.json")))


def read_cache(place, now):
    try:
        cached = json.loads(cache_path().read_text())
        if cached["location"] != place:
            return None
        value = cached["weather"]
        # Revalidate stored numbers/mapping, rather than trusting a partial cache.
        result = normalize({"current": {"temperature_2m": value["temperature"],
            "weather_code": value["code"], "is_day": int(value["isDay"]),
            "time": value["observedAt"]}, "current_units": {"temperature_2m": "°C"}}, now)
        age = now - value["fetchedAt"]
        if not 0 <= age < MAX_AGE:
            return None
        result["fetchedAt"] = value["fetchedAt"]
        return result
    except ERRORS:
        return None


def save_cache(place, weather):
    path = cache_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, staging = tempfile.mkstemp(dir=path.parent, prefix=".weather-")
    try:
        with os.fdopen(fd, "w") as output:
            json.dump({"location": place, "weather": weather}, output)
        os.replace(staging, path)
    finally:
        if os.path.exists(staging):
            os.unlink(staging)


def collect(force=False):
    now = time.time()
    try:
        place = location()
    except ERRORS:
        return {"ok": False, "available": False, "description": "Set location",
                "error": "Configure ~/.config/aeris-dashboard/weather.json"}
    cached = read_cache(place, now)
    if not force and cached and now - cached["fetchedAt"] < REFRESH:
        return {**cached, "ok": True, "available": True, "location": place["name"]}
    try:
        weather = fetch(place, now)
    except ERRORS:
        return {**(cached or {}), "ok": False, "available": cached is not None,
                "location": place["name"], "error": "Weather update unavailable",
                **({} if cached else {"description": "Unavailable"})}
    try:
        save_cache(place, weather)
    except OSError:
        pass  # A read-only cache must not discard a successful network response.
    return {**weather, "ok": True, "available": True, "location": place["name"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--refresh", action="store_true")
    print(json.dumps(collect(parser.parse_args().refresh), allow_nan=False))

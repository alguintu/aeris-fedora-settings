import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("weather", ROOT / "quickshell/aeris-dashboard/services/weather.py")
weather = importlib.util.module_from_spec(spec)
spec.loader.exec_module(weather)


class WeatherTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.config = Path(tmp.name) / "location.json"
        self.config.write_text(json.dumps({"name": "Test city", "latitude": 10, "longitude": 120}))
        env = patch.dict(os.environ, {"AERIS_WEATHER_CONFIG": str(self.config),
            "AERIS_WEATHER_CACHE": str(Path(tmp.name) / "cache.json")})
        env.start()
        self.addCleanup(env.stop)
        clock = patch.object(weather.time, "time", return_value=100000)
        clock.start()
        self.addCleanup(clock.stop)
        self.payload = {"current": {"temperature_2m": 28.4, "weather_code": 2,
            "is_day": 1, "time": 99900}, "current_units": {"temperature_2m": "°C"}}
        self.value = weather.normalize(self.payload, 100000)

    def test_all_wmo_conditions_and_night(self):
        for code in (0,1,2,3,45,48,51,53,55,56,57,61,63,65,66,67,71,73,75,77,80,81,82,85,86,95,96,99):
            for day in (0, 1):
                label, condition, icon = weather.condition(code, day)
                self.assertNotEqual(condition, "unknown")
                self.assertTrue(label and icon)
        self.assertEqual(weather.condition(0, 0)[1], "night")
        self.assertEqual(weather.condition(2, 0)[2], "weather-night-partly-cloudy")
        self.assertEqual(weather.condition(999, 1)[1], "unknown")

    def test_validation(self):
        for key, value in (("temperature_2m", None), ("temperature_2m", float("nan")),
                           ("is_day", 3), ("weather_code", None), ("time", 1)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                weather.normalize({**self.payload, "current": {**self.payload["current"], key: value}}, 100000)

    def test_success_persists_and_fresh_cache_avoids_network(self):
        with patch.object(weather, "fetch", return_value=self.value) as fetch:
            self.assertTrue(weather.collect()["ok"])
            self.assertTrue(weather.collect()["ok"])
            self.assertEqual(fetch.call_count, 1)

    def test_offline_uses_cache_without_new_timestamp(self):
        weather.save_cache(weather.location(), self.value)
        with patch.object(weather, "fetch", side_effect=OSError("offline")):
            result = weather.collect(force=True)
        self.assertFalse(result["ok"])
        self.assertTrue(result["available"])
        self.assertEqual(result["fetchedAt"], self.value["fetchedAt"])

    def test_expired_or_different_location_never_shown(self):
        for value, place in (({**self.value, "observedAt": 1}, weather.location()),
                             (self.value, {**weather.location(), "latitude": 20})):
            weather.save_cache(place, value)
            with patch.object(weather, "fetch", side_effect=OSError("offline")):
                self.assertFalse(weather.collect()["available"])

    def test_no_location_or_corrupt_cache(self):
        weather.cache_path().write_text("not JSON")
        with patch.object(weather, "fetch", side_effect=OSError("offline")):
            self.assertFalse(weather.collect()["available"])
        self.config.unlink()
        with patch.object(weather, "fetch") as fetch:
            self.assertEqual(weather.collect()["description"], "Set location")
            fetch.assert_not_called()

    def test_cache_write_failure_keeps_live_value(self):
        with patch.object(weather, "fetch", return_value=self.value), patch.object(weather, "save_cache", side_effect=OSError()):
            self.assertTrue(weather.collect()["ok"])


if __name__ == "__main__":
    unittest.main()

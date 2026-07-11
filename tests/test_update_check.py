from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from call_coding_clis.config import load_config
from call_coding_clis.update_check import (
    UpdateCache,
    cache_is_fresh,
    emit_post_run_update_notice,
    format_update_notice,
    load_cache,
    parse_version_tuple,
    refresh_cache,
    resolve_update_settings,
    save_cache,
    version_is_newer,
)


class VersionCompareTests(unittest.TestCase):
    def test_version_is_newer(self) -> None:
        self.assertTrue(version_is_newer("0.5.0", "0.4.1"))
        self.assertFalse(version_is_newer("0.4.1", "0.4.1"))
        self.assertFalse(version_is_newer("0.4.0", "0.4.1"))
        self.assertTrue(version_is_newer("v1.2.3", "1.2.2"))
        self.assertIsNone(parse_version_tuple("unknown"))


class CacheAndFetchTests(unittest.TestCase):
    def test_cache_roundtrip_and_freshness(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "update-check.json"
            cache = UpdateCache(
                checked_at=1000.0,
                current="0.4.1",
                latest="0.5.0",
                source="crates.io",
            )
            save_cache(cache, path)
            loaded = load_cache(path)
            assert loaded is not None
            self.assertEqual(loaded.latest, "0.5.0")
            self.assertTrue(cache_is_fresh(loaded, 24, now=1010.0))
            self.assertFalse(cache_is_fresh(loaded, 24, now=1000.0 + 90_000.0))

    def test_refresh_uses_fetcher_and_caches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "update-check.json"

            def fake_get(url: str, timeout: float) -> str | None:
                self.assertGreater(timeout, 0)
                if "crates.io" in url:
                    return json.dumps(
                        {
                            "crate": {
                                "max_stable_version": "9.9.9",
                                "max_version": "9.9.9",
                            }
                        }
                    )
                return None

            cache = refresh_cache(
                current="0.4.1",
                interval_hours=24,
                cache_path=path,
                http_get=fake_get,
                force=True,
                now=1234.0,
            )
            assert cache is not None
            self.assertEqual(cache.latest, "9.9.9")
            self.assertEqual(cache.source, "crates.io")
            self.assertTrue(path.is_file())

    def test_refresh_falls_back_to_github(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "update-check.json"

            def fake_get(url: str, timeout: float) -> str | None:
                if "github.com" in url:
                    return json.dumps({"tag_name": "v8.8.8"})
                return None

            cache = refresh_cache(
                current="0.4.1",
                cache_path=path,
                http_get=fake_get,
                force=True,
                now=1.0,
            )
            assert cache is not None
            self.assertEqual(cache.latest, "8.8.8")
            self.assertEqual(cache.source, "github")

    def test_emit_notice_when_update_available(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "update-check.json"
            save_cache(
                UpdateCache(
                    checked_at=10_000.0,
                    current="0.4.1",
                    latest="0.9.0",
                    source="crates.io",
                ),
                path,
            )
            settings = resolve_update_settings(
                config_check=True,
                config_auto_update=False,
                config_interval_hours=24,
            )
            with mock.patch(
                "call_coding_clis.update_check.time.time", return_value=10_010.0
            ):
                with open(os.devnull, "w", encoding="utf-8") as sink:
                    notice = emit_post_run_update_notice(
                        settings,
                        current="0.4.1",
                        cache_path=path,
                        spawn_update=False,
                        file=sink,
                    )
            self.assertIsNotNone(notice)
            assert notice is not None
            self.assertIn("0.9.0", notice)
            self.assertIn("cargo install ccc", notice)

    def test_emit_skips_when_disabled(self) -> None:
        settings = resolve_update_settings(
            config_check=False,
            config_auto_update=False,
            config_interval_hours=24,
        )
        with open(os.devnull, "w", encoding="utf-8") as sink:
            notice = emit_post_run_update_notice(
                settings,
                current="0.4.1",
                spawn_update=False,
                file=sink,
            )
        self.assertIsNone(notice)

    def test_format_auto_update_notice(self) -> None:
        text = format_update_notice("0.4.1", "0.5.0", auto_update=True)
        self.assertIn("background update", text)


class UpdateConfigTests(unittest.TestCase):
    def test_load_update_section(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.toml"
            path.write_text(
                """
[update]
check = false
auto_update = true
interval_hours = 12
""",
                encoding="utf-8",
            )
            config = load_config(path)
            self.assertFalse(config.update_check)
            self.assertTrue(config.auto_update)
            self.assertEqual(config.update_interval_hours, 12)

    def test_env_overrides(self) -> None:
        with mock.patch.dict(
            os.environ,
            {
                "CCC_UPDATE_CHECK": "0",
                "CCC_AUTO_UPDATE": "1",
                "CCC_UPDATE_INTERVAL_HOURS": "6",
            },
            clear=False,
        ):
            settings = resolve_update_settings(
                config_check=True,
                config_auto_update=False,
                config_interval_hours=24,
            )
        self.assertFalse(settings.check)
        self.assertTrue(settings.auto_update)
        self.assertEqual(settings.interval_hours, 6)


if __name__ == "__main__":
    unittest.main()

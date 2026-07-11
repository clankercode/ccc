"""Optional post-run version check and background auto-update helpers."""

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from typing import Callable

try:
    from importlib import metadata as importlib_metadata
except ImportError:  # pragma: no cover
    import importlib_metadata  # type: ignore

CRATES_API_URL = "https://crates.io/api/v1/crates/ccc"
GITHUB_RELEASE_URL = "https://api.github.com/repos/clankercode/ccc/releases/latest"
DEFAULT_INTERVAL_HOURS = 24
DEFAULT_FETCH_TIMEOUT_SECS = 2.0
CACHE_DIR_NAME = "ccc"
CACHE_FILE_NAME = "update-check.json"
VERSION_RE = re.compile(r"^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:[-+].*)?$")
_ROOT = Path(__file__).resolve().parents[2]
_VERSION_FILE = _ROOT / "VERSION"


@dataclass(slots=True)
class UpdateSettings:
    check: bool = True
    auto_update: bool = False
    interval_hours: int = DEFAULT_INTERVAL_HOURS


@dataclass(slots=True)
class UpdateCache:
    checked_at: float
    current: str
    latest: str
    source: str = ""

    @property
    def update_available(self) -> bool:
        return version_is_newer(self.latest, self.current)


Fetcher = Callable[[str, float], str | None]


def resolve_update_settings(
    config_check: bool = True,
    config_auto_update: bool = False,
    config_interval_hours: int = DEFAULT_INTERVAL_HOURS,
) -> UpdateSettings:
    check = _env_bool("CCC_UPDATE_CHECK", config_check)
    auto_update = _env_bool("CCC_AUTO_UPDATE", config_auto_update)
    interval_hours = config_interval_hours
    raw_interval = os.environ.get("CCC_UPDATE_INTERVAL_HOURS", "").strip()
    if raw_interval:
        try:
            parsed = int(raw_interval)
            if parsed > 0:
                interval_hours = parsed
        except ValueError:
            pass
    if interval_hours <= 0:
        interval_hours = DEFAULT_INTERVAL_HOURS
    return UpdateSettings(
        check=check,
        auto_update=auto_update,
        interval_hours=interval_hours,
    )


def current_version() -> str:
    try:
        version = _VERSION_FILE.read_text(encoding="utf-8").strip()
        if version:
            return version
    except OSError:
        pass
    try:
        return importlib_metadata.version("call-coding-clis")
    except importlib_metadata.PackageNotFoundError:
        return "unknown"


def resolve_cache_path() -> Path:
    explicit = os.environ.get("CCC_UPDATE_CACHE", "").strip()
    if explicit:
        return Path(explicit)
    xdg_cache = os.environ.get("XDG_CACHE_HOME", "").strip()
    if xdg_cache:
        return Path(xdg_cache) / CACHE_DIR_NAME / CACHE_FILE_NAME
    return Path.home() / ".cache" / CACHE_DIR_NAME / CACHE_FILE_NAME


def load_cache(path: Path | None = None) -> UpdateCache | None:
    cache_path = resolve_cache_path() if path is None else path
    try:
        payload = json.loads(cache_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeError):
        return None
    if not isinstance(payload, dict):
        return None
    try:
        checked_at = float(payload["checked_at"])
        current = str(payload["current"])
        latest = str(payload["latest"])
    except (KeyError, TypeError, ValueError):
        return None
    source = str(payload.get("source", ""))
    if not current or not latest:
        return None
    return UpdateCache(
        checked_at=checked_at,
        current=current,
        latest=latest,
        source=source,
    )


def save_cache(cache: UpdateCache, path: Path | None = None) -> None:
    cache_path = resolve_cache_path() if path is None else path
    try:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "checked_at": cache.checked_at,
            "current": cache.current,
            "latest": cache.latest,
            "source": cache.source,
        }
        cache_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    except OSError:
        return


def cache_is_fresh(cache: UpdateCache, interval_hours: int, now: float | None = None) -> bool:
    moment = time.time() if now is None else now
    max_age = max(1, interval_hours) * 3600
    return (moment - cache.checked_at) < max_age


def parse_version_tuple(version: str) -> tuple[int, int, int] | None:
    text = version.strip()
    if not text or text.lower() == "unknown":
        return None
    match = VERSION_RE.match(text)
    if match is None:
        return None
    major = int(match.group(1))
    minor = int(match.group(2) or 0)
    patch = int(match.group(3) or 0)
    return major, minor, patch


def version_is_newer(latest: str, current: str) -> bool:
    latest_parts = parse_version_tuple(latest)
    current_parts = parse_version_tuple(current)
    if latest_parts is None or current_parts is None:
        return False
    return latest_parts > current_parts


def default_http_get(url: str, timeout_secs: float) -> str | None:
    current = current_version()
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": f"ccc/{current} (https://github.com/clankercode/ccc)",
            "Accept": "application/json",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout_secs) as response:
            body = response.read()
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        return None
    try:
        return body.decode("utf-8")
    except UnicodeError:
        return None


def fetch_latest_version(
    *,
    timeout_secs: float = DEFAULT_FETCH_TIMEOUT_SECS,
    http_get: Fetcher | None = None,
) -> tuple[str, str] | None:
    getter = http_get or default_http_get
    crates_body = getter(CRATES_API_URL, timeout_secs)
    if crates_body:
        latest = _parse_crates_latest(crates_body)
        if latest:
            return latest, "crates.io"
    github_body = getter(GITHUB_RELEASE_URL, timeout_secs)
    if github_body:
        latest = _parse_github_latest(github_body)
        if latest:
            return latest, "github"
    return None


def refresh_cache(
    *,
    current: str | None = None,
    interval_hours: int = DEFAULT_INTERVAL_HOURS,
    timeout_secs: float = DEFAULT_FETCH_TIMEOUT_SECS,
    cache_path: Path | None = None,
    http_get: Fetcher | None = None,
    force: bool = False,
    now: float | None = None,
) -> UpdateCache | None:
    moment = time.time() if now is None else now
    path = resolve_cache_path() if cache_path is None else cache_path
    existing = load_cache(path)
    if existing is not None and not force and cache_is_fresh(existing, interval_hours, moment):
        return existing
    current_ver = current if current is not None else current_version()
    fetched = fetch_latest_version(timeout_secs=timeout_secs, http_get=http_get)
    if fetched is None:
        return existing
    latest, source = fetched
    cache = UpdateCache(
        checked_at=moment,
        current=current_ver,
        latest=latest,
        source=source,
    )
    save_cache(cache, path)
    return cache


def format_update_notice(current: str, latest: str, *, auto_update: bool = False) -> str:
    if auto_update:
        return (
            f"warning: ccc {latest} is available (you have {current}); "
            "starting background update via `cargo install ccc`"
        )
    return (
        f"warning: ccc {latest} is available (you have {current}); "
        "update with: cargo install ccc"
    )


def detect_install_method(executable: str | None = None) -> str:
    raw = executable if executable is not None else (sys.argv[0] if sys.argv else "")
    try:
        path = Path(raw).expanduser().resolve()
    except OSError:
        path = Path(raw)
    text = str(path).replace("\\", "/")
    if "/cargo/bin/" in text or text.endswith("/.cargo/bin/ccc"):
        return "cargo"
    if path.suffix == ".py" or "call_coding_clis" in text:
        return "pip"
    cargo_bin = Path.home() / ".cargo" / "bin" / "ccc"
    try:
        if cargo_bin.exists() and path.exists() and cargo_bin.samefile(path):
            return "cargo"
    except OSError:
        pass
    return "unknown"


def spawn_background_update(
    *,
    install_method: str | None = None,
    log_path: Path | None = None,
) -> Path | None:
    method = install_method if install_method is not None else detect_install_method()
    if method != "cargo":
        return None
    log = log_path if log_path is not None else resolve_cache_path().with_name("auto-update.log")
    try:
        log.parent.mkdir(parents=True, exist_ok=True)
    except OSError:
        return None
    try:
        with log.open("a", encoding="utf-8") as handle:
            handle.write(f"\n--- auto-update started {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} ---\n")
            handle.flush()
            subprocess.Popen(
                ["cargo", "install", "ccc", "--force"],
                stdout=handle,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
    except OSError:
        return None
    return log


def emit_post_run_update_notice(
    settings: UpdateSettings,
    *,
    current: str | None = None,
    cache_path: Path | None = None,
    http_get: Fetcher | None = None,
    timeout_secs: float = DEFAULT_FETCH_TIMEOUT_SECS,
    spawn_update: bool = True,
    file=None,
) -> str | None:
    if not settings.check:
        return None
    current_ver = current if current is not None else current_version()
    cache = refresh_cache(
        current=current_ver,
        interval_hours=settings.interval_hours,
        timeout_secs=timeout_secs,
        cache_path=cache_path,
        http_get=http_get,
    )
    if cache is None or not version_is_newer(cache.latest, current_ver):
        return None
    auto = settings.auto_update
    notice = format_update_notice(current_ver, cache.latest, auto_update=auto)
    print(notice, file=file if file is not None else sys.stderr)
    if auto and spawn_update:
        log = spawn_background_update()
        if log is None and detect_install_method() != "cargo":
            print(
                "warning: auto_update is enabled but this ccc install is not cargo-based; "
                "update manually with: cargo install ccc",
                file=file if file is not None else sys.stderr,
            )
        elif log is not None:
            print(f"warning: auto-update log: {log}", file=file if file is not None else sys.stderr)
    return notice


def _parse_crates_latest(body: str) -> str | None:
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        return None
    crate = payload.get("crate")
    if not isinstance(crate, dict):
        return None
    for key in ("max_stable_version", "max_version", "newest_version"):
        value = crate.get(key)
        if isinstance(value, str) and parse_version_tuple(value) is not None:
            return value.lstrip("v")
    return None


def _parse_github_latest(body: str) -> str | None:
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        return None
    tag = payload.get("tag_name") or payload.get("name")
    if not isinstance(tag, str):
        return None
    cleaned = tag.strip()
    if cleaned.lower().startswith("v"):
        cleaned = cleaned[1:]
    if parse_version_tuple(cleaned) is None:
        return None
    return cleaned


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None:
        return default
    normalized = raw.strip().lower()
    if normalized in {"", "1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off", "n"}:
        return False
    return default

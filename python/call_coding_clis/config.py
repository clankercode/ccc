from __future__ import annotations

import os
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    try:
        import tomli as tomllib
    except ModuleNotFoundError:
        tomllib = None

try:
    from .parser import AliasDef, CccConfig
except ImportError:
    from parser import AliasDef, CccConfig


CONFIG_DIR_NAME = "ccc"
CONFIG_FILE_NAME = "config.toml"


def _coerce_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return bool(value)
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "on"}
    return bool(value)


def _default_config_paths() -> list[Path]:
    paths: list[Path] = []
    xdg = os.environ.get("XDG_CONFIG_HOME", "")
    if xdg:
        paths.append(Path(xdg) / CONFIG_DIR_NAME / CONFIG_FILE_NAME)
    paths.append(Path.home() / ".config" / CONFIG_DIR_NAME / CONFIG_FILE_NAME)
    return paths


def load_config(path: str | Path | None = None) -> CccConfig:
    if tomllib is None:
        return CccConfig()

    if path is not None:
        return _load_from_file(Path(path))

    for candidate in _default_config_paths():
        if candidate.exists():
            return _load_from_file(candidate)

    return CccConfig()


def _load_from_file(path: Path) -> CccConfig:
    try:
        raw = path.read_bytes()
        data = tomllib.loads(raw.decode("utf-8"))
    except (OSError, ValueError):
        return CccConfig()

    config = CccConfig()

    defaults = data.get("defaults", {})
    if isinstance(defaults, dict):
        config.default_runner = defaults.get("runner", config.default_runner)
        config.default_provider = defaults.get("provider", config.default_provider)
        config.default_model = defaults.get("model", config.default_model)
        thinking = defaults.get("thinking")
        if thinking is not None:
            config.default_thinking = int(thinking)
        show_thinking = defaults.get("show_thinking")
        if show_thinking is not None:
            config.default_show_thinking = _coerce_bool(show_thinking)

    default_show_thinking = data.get("default_show_thinking")
    if default_show_thinking is not None:
        config.default_show_thinking = _coerce_bool(default_show_thinking)

    abbreviations = data.get("abbreviations", {})
    if isinstance(abbreviations, dict):
        config.abbreviations = {str(k): str(v) for k, v in abbreviations.items()}

    aliases = data.get("aliases", {})
    if isinstance(aliases, dict):
        for name, defn in aliases.items():
            if isinstance(defn, dict):
                alias = AliasDef(
                    runner=defn.get("runner"),
                    thinking=defn.get("thinking"),
                    show_thinking=defn.get("show_thinking"),
                    provider=defn.get("provider"),
                    model=defn.get("model"),
                    agent=defn.get("agent"),
                )
                if alias.thinking is not None:
                    alias.thinking = int(alias.thinking)
                if alias.show_thinking is not None:
                    alias.show_thinking = _coerce_bool(alias.show_thinking)
                config.aliases[str(name)] = alias

    return config

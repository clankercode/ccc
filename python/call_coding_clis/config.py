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
PROJECT_CONFIG_FILE_NAME = ".ccc.toml"


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
    home_path = Path.home() / ".config" / CONFIG_DIR_NAME / CONFIG_FILE_NAME
    paths.append(home_path)
    xdg = os.environ.get("XDG_CONFIG_HOME", "")
    if xdg:
        xdg_path = Path(xdg) / CONFIG_DIR_NAME / CONFIG_FILE_NAME
        if xdg_path != home_path:
            paths.append(xdg_path)
    try:
        cwd = Path.cwd()
    except OSError:
        return paths
    for directory in (cwd, *cwd.parents):
        candidate = directory / PROJECT_CONFIG_FILE_NAME
        if candidate.exists():
            paths.append(candidate)
            break
    return paths


def load_config(path: str | Path | None = None) -> CccConfig:
    if tomllib is None:
        return CccConfig()

    if path is not None:
        config = CccConfig()
        _load_from_file_into(Path(path), config)
        return config

    config = CccConfig()
    for candidate in _default_config_paths():
        if candidate.exists():
            _load_from_file_into(candidate, config)

    return config


def _load_from_file_into(path: Path, config: CccConfig) -> None:
    try:
        raw = path.read_bytes()
        data = tomllib.loads(raw.decode("utf-8"))
    except (OSError, ValueError):
        return

    defaults = data.get("defaults", {})
    if isinstance(defaults, dict):
        config.default_runner = defaults.get("runner", config.default_runner)
        config.default_provider = defaults.get("provider", config.default_provider)
        config.default_model = defaults.get("model", config.default_model)
        output_mode = defaults.get("output_mode")
        if output_mode is not None:
            config.default_output_mode = str(output_mode)
        thinking = defaults.get("thinking")
        if thinking is not None:
            config.default_thinking = int(thinking)
        show_thinking = defaults.get("show_thinking")
        if show_thinking is not None:
            config.default_show_thinking = _coerce_bool(show_thinking)
        sanitize_osc = defaults.get("sanitize_osc")
        if sanitize_osc is not None:
            config.default_sanitize_osc = _coerce_bool(sanitize_osc)

    default_output_mode = data.get("default_output_mode")
    if default_output_mode is not None:
        config.default_output_mode = str(default_output_mode)

    default_show_thinking = data.get("default_show_thinking")
    if default_show_thinking is not None:
        config.default_show_thinking = _coerce_bool(default_show_thinking)

    default_sanitize_osc = data.get("default_sanitize_osc")
    if default_sanitize_osc is not None:
        config.default_sanitize_osc = _coerce_bool(default_sanitize_osc)

    abbreviations = data.get("abbreviations", {})
    if isinstance(abbreviations, dict):
        config.abbreviations = {str(k): str(v) for k, v in abbreviations.items()}

    aliases = data.get("aliases", {})
    if isinstance(aliases, dict):
        for name, defn in aliases.items():
            if isinstance(defn, dict):
                alias = config.aliases.get(str(name), AliasDef())
                alias.runner = defn.get("runner", alias.runner)
                alias.thinking = defn.get("thinking", alias.thinking)
                alias.show_thinking = defn.get("show_thinking", alias.show_thinking)
                alias.sanitize_osc = defn.get("sanitize_osc", alias.sanitize_osc)
                alias.output_mode = defn.get("output_mode", alias.output_mode)
                alias.provider = defn.get("provider", alias.provider)
                alias.model = defn.get("model", alias.model)
                alias.agent = defn.get("agent", alias.agent)
                alias.prompt = defn.get("prompt", alias.prompt)
                if alias.thinking is not None:
                    alias.thinking = int(alias.thinking)
                if alias.show_thinking is not None:
                    alias.show_thinking = _coerce_bool(alias.show_thinking)
                if alias.sanitize_osc is not None:
                    alias.sanitize_osc = _coerce_bool(alias.sanitize_osc)
                config.aliases[str(name)] = alias

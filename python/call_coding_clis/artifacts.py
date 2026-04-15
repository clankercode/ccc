from __future__ import annotations

from dataclasses import dataclass, field
import os
from pathlib import Path
import secrets
import sys
import time
from typing import Callable, TextIO


RUN_ROOT_DIR_NAME = "ccc"
RUNS_DIR_NAME = "runs"
OUTPUT_FILE_NAME = "output.txt"
TRANSCRIPT_TEXT_FILE_NAME = "transcript.txt"
TRANSCRIPT_JSONL_FILE_NAME = "transcript.jsonl"


def resolve_state_root() -> Path:
    xdg_state_home = os.environ.get("XDG_STATE_HOME", "").strip()
    if xdg_state_home:
        return Path(xdg_state_home)
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support"
    if sys.platform.startswith("win"):
        local_app_data = os.environ.get("LOCALAPPDATA", "").strip()
        if local_app_data:
            return Path(local_app_data)
        return Path.home() / "AppData" / "Local"
    return Path.home() / ".local" / "state"


def _generate_run_id() -> str:
    timestamp = time.time_ns()
    pid = os.getpid()
    suffix = secrets.token_hex(3)
    return f"{timestamp:x}-{pid:x}-{suffix}"


def _canonical_run_dir_prefix(run_dir_prefix: str | None) -> str | None:
    if run_dir_prefix is None:
        return None
    name = run_dir_prefix.strip().lower()
    if not name:
        return None
    if name in {"oc", "opencode"}:
        return "opencode"
    if name in {"cc", "claude"}:
        return "claude"
    if name in {"c", "cx", "codex"}:
        return "codex"
    if name in {"k", "kimi"}:
        return "kimi"
    if name in {"cr", "crush"}:
        return "crush"
    if name in {"rc", "roocode"}:
        return "roocode"
    if name in {"cu", "cursor"}:
        return "cursor"
    if name in {"g", "gemini"}:
        return "gemini"
    return name


def create_run_directory(
    state_root: Path | None = None,
    *,
    run_id_factory: Callable[[], str] | None = None,
    run_dir_prefix: str | None = None,
) -> Path | None:
    base_root = resolve_state_root() if state_root is None else Path(state_root)
    runs_root = base_root / RUN_ROOT_DIR_NAME / RUNS_DIR_NAME
    try:
        runs_root.mkdir(parents=True, exist_ok=True)
    except OSError:
        return None

    factory = run_id_factory or _generate_run_id
    prefix = _canonical_run_dir_prefix(run_dir_prefix)
    for _ in range(128):
        run_id = factory()
        run_name = f"{prefix}-{run_id}" if prefix else run_id
        run_dir = runs_root / run_name
        try:
            run_dir.mkdir(parents=False, exist_ok=False)
        except FileExistsError:
            continue
        except OSError:
            return None
        return run_dir
    return None


@dataclass(slots=True)
class RunArtifactWriter:
    run_dir: Path
    transcript_name: str
    footer_enabled: bool = True
    transcript_warning: str | None = None
    _transcript_handle: TextIO | None = field(default=None, repr=False, compare=False)

    @property
    def output_path(self) -> Path:
        return self.run_dir / OUTPUT_FILE_NAME

    @property
    def transcript_path(self) -> Path:
        return self.run_dir / self.transcript_name

    def write_transcript(self, text: str) -> None:
        if self._transcript_handle is None:
            return
        try:
            self._transcript_handle.write(text)
            self._transcript_handle.flush()
        except OSError:
            try:
                self._transcript_handle.close()
            finally:
                self._transcript_handle = None
            raise

    def write_output(self, text: str) -> None:
        self.output_path.write_text(text, encoding="utf-8")

    def close(self) -> None:
        if self._transcript_handle is None:
            return
        self._transcript_handle.close()
        self._transcript_handle = None

    def footer_line(self) -> str | None:
        if not self.footer_enabled:
            return None
        return f">> ccc:output-log >> {self.run_dir}"

    @classmethod
    def create(
        cls,
        *,
        transcript_name: str,
        footer_enabled: bool = True,
        state_root: Path | None = None,
        run_id_factory: Callable[[], str] | None = None,
        runner_name: str | None = None,
    ) -> RunArtifactWriter | None:
        run_dir = create_run_directory(
            state_root,
            run_id_factory=run_id_factory,
            run_dir_prefix=runner_name,
        )
        if run_dir is None:
            return None
        try:
            handle = (run_dir / transcript_name).open("w", encoding="utf-8")
        except OSError as exc:
            handle = None
            transcript_warning = f"warning: could not create {transcript_name}: {exc}"
        else:
            transcript_warning = None
        return cls(
            run_dir=run_dir,
            transcript_name=transcript_name,
            footer_enabled=footer_enabled,
            transcript_warning=transcript_warning,
            _transcript_handle=handle,
        )


def create_run_artifact_writer(
    *,
    transcript_filename: str,
    footer_enabled: bool = True,
    state_root: Path | None = None,
    run_id_factory: Callable[[], str] | None = None,
    runner_name: str | None = None,
) -> RunArtifactWriter | None:
    return RunArtifactWriter.create(
        transcript_name=transcript_filename,
        footer_enabled=footer_enabled,
        state_root=state_root,
        run_id_factory=run_id_factory,
        runner_name=runner_name,
    )

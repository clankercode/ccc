from __future__ import annotations

from dataclasses import dataclass, field
import os
import queue
import threading
import subprocess
from typing import Callable


@dataclass(slots=True)
class CommandSpec:
    argv: list[str]
    stdin_text: str | None = None
    cwd: str | None = None
    env: dict[str, str] = field(default_factory=dict)


@dataclass(slots=True)
class CompletedRun:
    argv: list[str]
    exit_code: int
    stdout: str
    stderr: str


Executor = Callable[..., subprocess.CompletedProcess[str]]
StreamCallback = Callable[[str, str], None]
StreamExecutor = Callable[
    [CommandSpec, StreamCallback], subprocess.CompletedProcess[str] | object
]


class Runner:
    def __init__(
        self,
        executor: Executor | None = None,
        stream_executor: StreamExecutor | None = None,
    ) -> None:
        self._executor = executor or subprocess.run
        self._stream_executor = stream_executor or self._default_stream_executor

    def run(self, spec: CommandSpec) -> CompletedRun:
        try:
            completed = self._executor(
                spec.argv,
                input=spec.stdin_text,
                stdin=subprocess.DEVNULL if spec.stdin_text is None else subprocess.PIPE,
                cwd=spec.cwd,
                env=self._merged_env(spec.env),
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError as error:
            return CompletedRun(
                argv=list(spec.argv),
                exit_code=1,
                stdout="",
                stderr=f"failed to start {spec.argv[0]}: {error}\n",
            )
        return CompletedRun(
            argv=list(spec.argv),
            exit_code=int(completed.returncode),
            stdout=str(completed.stdout),
            stderr=str(completed.stderr),
        )

    def stream(self, spec: CommandSpec, on_event: StreamCallback) -> CompletedRun:
        completed = self._stream_executor(spec, on_event)
        return CompletedRun(
            argv=list(spec.argv),
            exit_code=int(completed.returncode),
            stdout=str(completed.stdout),
            stderr=str(completed.stderr),
        )

    def _default_stream_executor(
        self, spec: CommandSpec, on_event: StreamCallback
    ) -> subprocess.CompletedProcess[str]:
        try:
            process = subprocess.Popen(
                spec.argv,
                stdin=subprocess.PIPE
                if spec.stdin_text is not None
                else subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=spec.cwd,
                env=self._merged_env(spec.env),
                text=True,
            )
        except OSError as error:
            stderr = f"failed to start {spec.argv[0]}: {error}\n"
            on_event("stderr", stderr)
            return subprocess.CompletedProcess(spec.argv, 1, "", stderr)

        if spec.stdin_text is not None and process.stdin is not None:
            process.stdin.write(spec.stdin_text)
            process.stdin.close()

        event_queue: queue.Queue[tuple[str, str] | tuple[str, None]] = queue.Queue()
        stdout_chunks: list[str] = []
        stderr_chunks: list[str] = []

        def pump(channel: str, stream) -> None:
            try:
                while True:
                    chunk = stream.read(1)
                    if not chunk:
                        break
                    event_queue.put((channel, chunk))
            finally:
                stream.close()
                event_queue.put((channel, None))

        stdout_thread = threading.Thread(
            target=pump,
            args=("stdout", process.stdout),
            daemon=True,
        )
        stderr_thread = threading.Thread(
            target=pump,
            args=("stderr", process.stderr),
            daemon=True,
        )
        stdout_thread.start()
        stderr_thread.start()

        closed = 0
        while closed < 2:
            channel, chunk = event_queue.get()
            if chunk is None:
                closed += 1
                continue
            if channel == "stdout":
                stdout_chunks.append(chunk)
            else:
                stderr_chunks.append(chunk)
            on_event(channel, chunk)

        process.wait()
        stdout = "".join(stdout_chunks)
        stderr = "".join(stderr_chunks)
        return subprocess.CompletedProcess(
            spec.argv, process.returncode, stdout, stderr
        )

    def _merged_env(self, override: dict[str, str]) -> dict[str, str]:
        env = dict(os.environ)
        env.update(override)
        return env

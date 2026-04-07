# asm-x86_64 — Pure NASM Linux x86-64 `ccc` Binary

## Overview

Minimal ELF64 static binary implementing the `ccc` CLI contract using raw Linux syscalls and zero libc dependency. Single NASM source file assembled and linked into a standalone executable.

## Toolchain & Build

### Assembler: NASM (Intel syntax)

- Source: `asm-x86_64/ccc.asm`
- Output: `asm-x86_64/ccc` (ELF64 executable)

### Makefile targets

```makefile
all: ccc

ccc: ccc.asm
    nasm -f elf64 -o ccc.o ccc.asm
    ld -o ccc ccc.o

clean:
    rm -f ccc.o ccc
```

No `-g` by default. A `debug` target can add `-g -F dwarf` for GDB use.

### Why NASM over GAS

- Intel syntax is more readable for systems-level register work
- No implicit C preamble, no `.global _start` confusion
- Direct `%use` of `smartalign` if needed
- Flat binary semantics map cleanly to our syscall-only approach

## Linux Syscalls Used

| Syscall | Nr (x86-64) | Purpose |
|---------|-------------|---------|
| `write`  | 1           | Error messages to stderr (fd 2) |
| `fork`   | 57          | Create child process |
| `execve` | 59          | Execute `opencode run "<prompt>"` |
| `waitpid`| 61          | Reap child, extract exit status |
| `exit`   | 60          | Terminate with exit code |

Syscall convention: `rax` = syscall number, args in `rdi rsi rdx r10 r8 r9`, return in `rax`. Clobber `rcx` and `r11`.

## Program Entry & Stack Layout

At `_start` the kernel places `[argc]` at `(%rsp)`, followed by `argv[0..argc-1]` (null-terminated), then `envp[0..]`, then `NULL`. We do not touch `envp`.

```
%rsp → argc          (8 bytes, qword)
        argv[0]       (pointer to "ccc")
        argv[1]       (pointer to prompt string)
        argv[2]       (NULL)
        ...
        envp[0]
        ...
        NULL
```

## Execution Flow

```
_start
  ├── check argc == 2 → if not: write_str(stderr, "usage: ccc \"<Prompt>\"\n"); exit(1)
  ├── trim leading/trailing whitespace on argv[1] in-place
  ├── check prompt non-empty after trim → if empty: write_str(stderr, "prompt must not be empty\n"); exit(1)
  ├── check CCC_REAL_OPENCODE env var (scan envp for "CCC_REAL_OPENCODE=")
  │     └── if found: use value as binary name
  │     └── if not found: default "opencode"
  ├── build argv for execve on stack:
  │     [runner_ptr, "run"_ptr, prompt_ptr, NULL]
  ├── fork()
  │     ├── child == 0:
  │     │     execve(argv_exec, argvp, NULL)   — pass envp for inherited env
  │     │     if execve returns (always error):
  │     │       write "failed to start <name>: execve failed\n" to stderr
  │     │       exit(127)
  │     └── parent (child > 0):
  │           waitpid(child, &status, 0)
  │           extract WIFEXITED/WEXITSTATUS from status (raw int)
  │           exit(child_exit_code)
  └── fork error: write "fork failed\n" to stderr; exit(1)
```

## Prompt Handling — Stack-Only, No Heap

### Whitespace check (reused from C impl logic)

Input: `rsi` = pointer to null-terminated string.
Scan byte-by-byte. Whitespace chars: `0x09` (tab), `0x0A` (LF), `0x0D` (CR), `0x20` (space).

### Trim in-place

Leading: advance pointer past whitespace bytes. Trailing: find last non-whitespace byte, write `0x00` after it.

The prompt is in the argv area placed by the kernel. We modify it in-place — this is safe because the process image owns the stack and we never return the modified string to anyone else.

### Empty/whitespace rejection

After trim, if first byte is `0x00` → empty prompt. Emit `"prompt must not be empty\n"` to stderr and `exit(1)`.

### Usage message (argc mismatch)

If `argc != 2`, emit `"usage: ccc \"<Prompt>\"\n"` to stderr and `exit(1)`. This matches the exact format used by the C implementation (`c/src/ccc.c:37`) and expected by the contract test `assert_rejects_missing_prompt` which checks for `'ccc "<Prompt>"'` in stderr.

## Exit Code Forwarding

`waitpid` returns status in `rsi` (pointed-to int). Extract the low 8 bits:

```
mov eax, [status]        ; raw wait status
and eax, 0x7f            ; WIFEXITED check: (status & 0x7f) == 0
jnz  .not_exited
mov eax, [status]
shr eax, 8               ; WEXITSTATUS: (status >> 8) & 0xff
jmp  .exit
.not_exited:
mov eax, 1               ; killed by signal → exit 1
.exit:
; rax = child exit code
mov rdi, rax
mov rax, 60              ; sys_exit
syscall
```

## CCC_REAL_OPENCODE Override

Scan `envp` (after `argv` NULL terminator) for a string starting with `CCC_REAL_OPENCODE=`. If found, the pointer past the `=` sign is the runner binary path. If not found, default to the literal `"opencode"`.

This allows the existing `test_ccc_contract.py` to work: the test writes an `opencode` stub to a temp `bin/` dir and puts it first in `PATH`. We rely on the inherited environment, so `envp` must be passed to `execve` (third argument), not `NULL`. The child inherits PATH and finds the stub.

## Error Messages

All error output goes to fd 2 (stderr) via `sys_write`:

| Condition | Message | Exit code |
|-----------|---------|-----------|
| `argc != 2` | `usage: ccc "<Prompt>"\n` | 1 |
| Empty/whitespace prompt | `prompt must not be empty\n` | 1 |
| `fork` returns -1 | `fork failed\n` | 1 |
| `execve` fails (child) | `failed to start <name>: execve failed\n` | 127 |

Messages match the C implementation's semantics. The `execve` error is deliberately simpler than the C version's `strerror(errno)` since we have no libc for errno/string conversion — a hardcoded suffix is sufficient and the contract only requires that startup-failure stderr contains `"failed to start"`.

## execve Argument Layout

`execve(filename, argv, envp)`:

```
Stack region (built in .bss or reserved stack space):
  filename:  pointer to runner string ("opencode" or env override)
  argv[0]:   pointer to runner string
  argv[1]:   pointer to "run" literal
  argv[2]:   pointer to trimmed prompt string
  argv[3]:   NULL (0)
  envp:      pointer to original envp from kernel stack
```

`rdi` = filename pointer, `rsi` = pointer to argv array, `rdx` = pointer to original envp.

## Data Sections

### `.rodata`

- `msg_usage`: `"usage: ccc \"<Prompt>\"\n"` (null-terminated)
- `msg_empty`: `"prompt must not be empty\n"` (null-terminated)
- `msg_fork`: `"fork failed\n"` (null-terminated)
- `msg_exec_prefix`: `"failed to start "` (null-terminated)
- `msg_exec_suffix`: `": execve failed\n"` (null-terminated)
- `str_run`: `"run"` (null-terminated)
- `str_opencode`: `"opencode"` (null-terminated)
- `env_key`: `"CCC_REAL_OPENCODE="` (null-terminated)

### `.bss`

- `exec_argv`: 4 qwords (argv pointers for execve: [runner, "run", prompt, NULL])
- `status_buf`: 4 bytes (waitpid status)
- `runner_buf`: 256 bytes (storage for env override path copy, if needed)

## Linux x86-64 ABI Notes

- Stack must be 16-byte aligned before making a syscall (kernel doesn't require this, but good practice)
- Red zone below `%rsp` is 128 bytes — we stay above it
- Register preservation: syscalls clobber `rcx` and `r11`
- We do not call any C functions, so no need to maintain full ABI callee-saved registers
- `_start` is the entry point; no return address on stack

## File Structure

```
asm-x86_64/
  PLAN.md          this file
  Makefile         nasm + ld build
  ccc.asm          single source file, all code + data
```

## Test Strategy

### Existing contract tests (`tests/test_ccc_contract.py`)

The Python contract test suite has four assertions that the ASM binary must satisfy:

1. **Happy path** (`test_cross_language_ccc_happy_path`): `ccc "Fix the failing tests"` → exit 0, stdout = `"opencode run Fix the failing tests\n"`, stderr empty
2. **Empty prompt** (`test_cross_language_ccc_rejects_empty_prompt`): `ccc ""` → exit 1, stdout empty, stderr non-empty
3. **Missing argument** (`test_cross_language_ccc_requires_one_prompt_argument`): `ccc` (no args) → exit 1, stdout empty, stderr contains `ccc "<Prompt>"`
4. **Whitespace prompt** (`test_cross_language_ccc_rejects_whitespace_only_prompt`): `ccc "   "` → exit 1, stdout empty, stderr non-empty

To integrate: add a step in each test method that runs `./asm-x86_64/ccc` the same way the C binary is tested. The test stub writes an `opencode` script to a temp `bin/` dir and prepends it to `PATH`. Since we pass `envp` through to `execve`, this works.

### Additional ASM-specific tests (optional Makefile target)

```makefile
test: ccc
    @echo "=== argc check ==="
    ./ccc; echo "exit: $$?"
    ./ccc a b; echo "exit: $$?"
    @echo "=== empty prompt ==="
    ./ccc ""; echo "exit: $$?"
    @echo "=== whitespace prompt ==="
    ./ccc "   "; echo "exit: $$?"
    @echo "=== happy path ==="
    PATH="$$PWD/test-stub:$$PATH" ./ccc "hello world"; echo "exit: $$?"
```

### Startup failure test

With a nonexistent `CCC_REAL_OPENCODE` path, stderr must contain `"failed to start"`. This mirrors the contract test requirement:

```bash
CCC_REAL_OPENCODE=/nonexistent/binary ./ccc "test"
# Expect: stderr contains "failed to start", exit code 127
```

## Out of Scope

- No library (`libccc.a` / `.so`) — binary only
- No streaming — child stdout/stderr go directly to inherited fds (no capture/pipe)
- No stdin forwarding — child inherits parent stdin (fd 0)
- No CWD or env overrides — child inherits parent's cwd and full environment
- No `build_prompt_spec` public API
- No macOS, 32-bit, or non-x86-64 support
- No `strerror` or `errno` — error messages are fixed strings
- No dynamic linking — fully static

## Implementation Checklist

- [ ] `ccc.asm`: `_start` entry, argc check
- [ ] `ccc.asm`: in-place prompt trim (leading + trailing whitespace)
- [ ] `ccc.asm`: empty/whitespace rejection with stderr message
- [ ] `ccc.asm`: envp scan for `CCC_REAL_OPENCODE`
- [ ] `ccc.asm`: build execve argv array on stack
- [ ] `ccc.asm`: fork + execve child, with error message on exec failure
- [ ] `ccc.asm`: parent waitpid + exit code extraction + forwarding
- [ ] `ccc.asm`: fork failure error path
- [ ] `Makefile`: all, ccc, clean, test targets
- [ ] Pass all four contract test cases
- [ ] Verify binary is static (no libc): `ldd ./ccc` → "not a dynamic executable"

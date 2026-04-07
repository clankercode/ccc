# asm-x86_64 — Pure NASM Linux x86-64 `ccc` Binary

## Overview

Minimal ELF64 static binary implementing the `ccc` CLI contract using raw Linux syscalls and zero libc dependency. Single NASM source file assembled and linked into a standalone executable.

## Prerequisites

- **NASM** ≥ 2.14 (`nasm --version`)
- **GNU ld** (binutils, typically pre-installed on Linux)
- **Linux x86-64** kernel (syscalls are Linux-specific)

Install on Debian/Ubuntu: `sudo apt install nasm binutils`
Install on Fedora:     `sudo dnf install nasm binutils`
Install on Arch:       `sudo pacman -S nasm binutils`

## Toolchain & Build

### Assembler: NASM (Intel syntax)

- Source: `asm-x86_64/ccc.asm`
- Output: `asm-x86_64/ccc` (ELF64 executable)

### Makefile

```makefile
NASM  := nasm
LD    := ld
FLAGS := -f elf64

.PHONY: all clean debug test test-contract static-check

all: ccc

ccc: ccc.asm
	$(NASM) $(FLAGS) -o ccc.o ccc.asm
	$(LD) -o ccc ccc.o

debug: ccc.asm
	$(NASM) $(FLAGS) -g -F dwarf -o ccc.o ccc.asm
	$(LD) -o ccc ccc.o

static-check: ccc.asm
	@echo "--- Verifying no dynamic dependencies ---"
	$(NASM) $(FLAGS) -o ccc.o ccc.asm && $(LD) -o ccc ccc.o
	ldd ./ccc 2>&1 | grep -q "not a dynamic executable" && echo "OK: static" || echo "FAIL: has dynamic deps"
	file ./ccc

clean:
	rm -f ccc.o ccc

test: ccc test-stub/opencode
	@echo "=== argc check (no args) ==="
	./ccc; echo "exit: $$?"
	@echo "=== argc check (too many args) ==="
	./ccc a b; echo "exit: $$?"
	@echo "=== empty prompt ==="
	./ccc ""; echo "exit: $$?"
	@echo "=== whitespace prompt ==="
	./ccc "   "; echo "exit: $$?"
	@echo "=== happy path ==="
	PATH="$$PWD/test-stub:$$PATH" ./ccc "hello world"; echo "exit: $$?"
	@echo "=== startup failure (nonexistent runner) ==="
	CCC_REAL_OPENCODE=/nonexistent/binary ./ccc "test" 2>&1; echo "exit: $$?"

test-contract: ccc
	python3 -m pytest ../tests/test_ccc_contract.py -v --tb=short -k "contract" 2>&1 || true
	@echo "NOTE: ASM binary must be registered in test_ccc_contract.py (see Cross-Language Test Registration section)"

test-stub/opencode:
	@mkdir -p test-stub
	@printf '#!/bin/sh\nif [ "$$1" != "run" ]; then\n  exit 9\nfi\nshift\nprintf "opencode run %%s\\n" "$$1"\n' > test-stub/opencode
	@chmod +x test-stub/opencode
```

**Build from repo root:**
```bash
make -C asm-x86_64          # builds asm-x86_64/ccc
make -C asm-x86_64 test     # runs quick smoke tests
make -C asm-x86_64 clean    # removes artifacts
```

**Build standalone (no Makefile):**
```bash
cd asm-x86_64
nasm -f elf64 -o ccc.o ccc.asm
ld -o ccc ccc.o
./ccc "hello world"
```

### Why NASM over GAS

- Intel syntax is more readable for systems-level register work
- No implicit C preamble, no `.global _start` confusion
- Direct `%use` of `smartalign` if needed
- Flat binary semantics map cleanly to our syscall-only approach

## Linux Syscalls Used

| Syscall     | Nr (x86-64) | Purpose |
|-------------|-------------|---------|
| `write`     | 1           | Error messages to stderr (fd 2) |
| `fork`      | 57          | Create child process |
| `execve`    | 59          | Execute `opencode run "<prompt>"` |
| `waitpid`   | 61          | Reap child, extract exit status |
| `exit_group`| 231         | Terminate process with exit code |

> **Why `exit_group` (231) instead of `exit` (60)?** `exit` only terminates the calling thread. `exit_group` terminates all threads in the process. Since we are single-threaded both are functionally equivalent, but `exit_group` is the canonical syscall for process termination on modern Linux and avoids any surprise if the binary is ever linked against code that spawns threads. Using `exit_group` matches what glibc's `exit()` wrapper emits internally.

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

### Whitespace definition

The C implementation uses `isspace()` from `<ctype.h>`, which on glibc matches: space (0x20), tab (0x09), newline (0x0A), vertical-tab (0x0B), form-feed (0x0C), carriage-return (0x0D). **The ASM implementation must match this exact set** to avoid behavioral divergence. Hardcode all six byte values in a comparison macro or lookup.

> **Review note:** The original plan listed only 4 whitespace chars (tab, LF, CR, space). This missed VT (0x0B) and FF (0x0C). Since `isspace()` in the C impl includes them, the ASM binary must too — otherwise `" \v "` would be rejected by C but accepted (after trim) by ASM.

### Trim in-place

Input: pointer to null-terminated string.
Leading: advance pointer past whitespace bytes. Trailing: find last non-whitespace byte, write `0x00` after it.

The prompt is in the argv area placed by the kernel. We modify it in-place — this is safe because the process image owns the stack and we never return the modified string to anyone else.

### Empty-prompt check

After trim, if first byte is `0x00` → empty prompt. Emit `"prompt must not be empty\n"` to stderr and `exit(1)`.

> **Review note:** The C impl (`c/src/ccc.c:43`) checks `strlen(prompt) == 0 || is_whitespace_only(prompt)` after trim. The `is_whitespace_only` branch is **dead code** after `trim_in_place` — trim strips all leading/trailing whitespace, so a string that was whitespace-only becomes empty (strlen==0). The ASM impl correctly only needs to check for the null terminator after trim.

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

## Helper Routines

### `write_str(fd, msg_ptr, msg_len)`

Used by all error paths. Must handle **partial writes** — `sys_write` may return fewer bytes than requested (e.g., if stderr is redirected to a pipe with a full buffer, or on EINTR). Loop until all bytes are written.

```
; Input: rdi = fd, rsi = msg ptr, rdx = msg length
; Clobbers: rax, rcx, r11, rdx
.write_str:
.loop:
    mov rax, 1           ; sys_write
    syscall
    test rax, rax
    jle  .done            ; error or EOF — silently stop (best-effort)
    add  rsi, rax         ; advance pointer
    sub  rdx, rax         ; decrease remaining count
    jnz  .loop
.done:
    ret
```

### `strlen(ptr)`

Returns length in `rax` of null-terminated string at `rsi`.

### `is_whitespace(byte_in_al)`

Returns `ZF=1` (je taken) if `al` is any of: 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20. Implemented as a lookup into a 256-byte bitmask or as a cascade of `cmp`/`je` instructions.

## CCC_REAL_OPENCODE Override

Scan `envp` (after `argv` NULL terminator) for a string starting with `"CCC_REAL_OPENCODE="` (length 19). Compare the first 19 bytes; if they match, the pointer at offset +19 is the runner binary path. If not found, default to the literal `"opencode"`.

> **Review note:** The original plan said "starting with" which could falsely match a longer key like `CCC_REAL_OPENCODE_EXTRA=foo`. Use an exact prefix-length match (19 bytes) followed by a check that byte 19 is not a null (i.e., there is a value after the `=`).

Copy the env value into `runner_buf` (`.bss`, 256 bytes) to guarantee null-termination and avoid buffer issues. If the env value is ≥ 256 bytes, truncate and null-terminate — this is an edge case that only affects testing and the binary path won't work at that length anyway.

## Error Messages

All error output goes to fd 2 (stderr) via `sys_write` (through the `write_str` helper):

| Condition | Message | Exit code |
|-----------|---------|-----------|
| `argc != 2` | `usage: ccc "<Prompt>"\n` | 1 |
| Empty/whitespace prompt | `prompt must not be empty\n` | 1 |
| `fork` returns -1 | `fork failed\n` | 1 |
| `execve` fails (child) | `failed to start <name>: execve failed\n` | 127 |

Messages match the C implementation's semantics. The `execve` error is deliberately simpler than the C version's `strerror(errno)` since we have no libc for errno/string conversion — a hardcoded suffix is sufficient and the contract only requires that startup-failure stderr contains `"failed to start"`.

### `execve` error message construction

The `"failed to start <name>: execve failed\n"` message must be constructed at runtime since `<name>` is dynamic. Strategy:

1. `write_str(stderr, msg_exec_prefix)`  — `"failed to start "`
2. `write_str(stderr, runner_ptr, runner_len)` — the runner name
3. `write_str(stderr, msg_exec_suffix)`  — `": execve failed\n"`

The runner name length is already known from the envp scan or defaults to 7 (strlen("opencode")).

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
- `runner_buf`: 256 bytes (storage for env override path copy, guaranteed null-terminated)

### `.note.GNU-stack` (required)

```
section .note.GNU-stack noalloc noexec nowrite progbits
```

Without this section, GNU `ld` may mark the stack as executable (depending on linker version and defaults). Adding `noexec` explicitly prevents this and suppresses warnings on modern systems.

## ELF Structure

The resulting binary is a minimal ELF64 executable:

- **Type:** `ET_EXEC` (2) — `ld` default for raw object files
- **Machine:** `EM_X86_64` (62) — set by `nasm -f elf64`
- **Entry point:** `_start` — set by `ld` default (first `.text` symbol)
- **Program headers:** `PT_LOAD` for `.text` and `.rodata` (read+exec), `.data`/`.bss` (read+write)
- **No interpreter:** fully static, no `PT_INTERP` — verify with `ldd ./ccc` → `"not a dynamic executable"`
- **No section header table stripping needed** for basic correctness, but `strip ./ccc` can reduce size for distribution

## Linux x86-64 ABI Notes

- **Syscalls do not require 16-byte stack alignment.** The kernel entry/exit path handles `rsp` internally. (The 16-byte alignment rule only applies to calling C functions via `call` instruction — which we never do.)
- Red zone below `%rsp` is 128 bytes — we stay above it
- Register preservation: syscalls clobber `rcx` and `r11`; all other registers are preserved across syscalls
- We do not call any C functions, so no need to maintain full ABI callee-saved registers
- `_start` is the entry point; no return address on stack
- `fork()` in the child returns with the exact same register state as the parent at the point of the syscall — only `rax` changes (child pid or 0). All other registers are preserved.

## File Structure

```
asm-x86_64/
  PLAN.md          this file
  Makefile         nasm + ld build, test, static-check
  ccc.asm          single source file, all code + data
  test-stub/
    opencode       shell script test double (generated by Makefile)
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

# PHP Implementation Plan — call-coding-clis

## 0. Build & Run Instructions

```bash
cd php

composer install          # install PHPUnit dev dependency, dump autoloader

# Run all tests
vendor/bin/phpunit

# Run specific suite
vendor/bin/phpunit --testsuite unit
vendor/bin/phpunit --testsuite integration

# Run CLI directly
php bin/ccc "Fix the failing tests"

# CLI is also executable via shebang after chmod +x
chmod +x bin/ccc
./bin/ccc "Fix the failing tests"
```

No build step required — PHP is interpreted. `composer install` is only needed for autoloading and dev dependencies.

## 1. Composer Package Structure

```
php/
├── composer.json
├── phpunit.xml
├── bin/
│   └── ccc              # CLI entry point (chmod +x, #!/usr/bin/env php)
├── src/
│   ├── CommandSpec.php
│   ├── CompletedRun.php
│   ├── Runner.php
│   └── build_prompt_spec.php
└── tests/
    ├── Unit/
    │   └── BuildPromptSpecTest.php
    └── Integration/
        └── RunnerTest.php
```

`composer.json`:

```json
{
    "name": "call-coding-clis/php",
    "description": "PHP library and CLI for call-coding-clis",
    "type": "library",
    "require": {
        "php": ">=8.2"
    },
    "require-dev": {
        "phpunit/phpunit": "^10|^11"
    },
    "autoload": {
        "psr-4": {
            "CallCodingClis\\": "src/"
        }
    },
    "autoload-dev": {
        "psr-4": {
            "CallCodingClis\\Tests\\": "tests/"
        }
    },
    "bin": ["bin/ccc"]
}
```

No external runtime dependencies. `proc_open` from the standard library is sufficient.

## 2. Library API

All source files must begin with `declare(strict_types=1);`.

### `CommandSpec` — `src/CommandSpec.php`

```php
declare(strict_types=1);

namespace CallCodingClis;

readonly class CommandSpec
{
    public function __construct(
        public array $argv,
        public ?string $stdinText = null,
        public ?string $cwd = null,
        public array $env = [],
    ) {}
}
```

Uses PHP 8.2 `readonly class` for immutability on the entire value object. Builder-style methods (`withStdin`, `withCwd`, `withEnv`) are unnecessary given the small surface; named args suffice.

### `CompletedRun` — `src/CompletedRun.php`

```php
declare(strict_types=1);

namespace CallCodingClis;

readonly class CompletedRun
{
    public function __construct(
        public array $argv,
        public int $exitCode,
        public string $stdout,
        public string $stderr,
    ) {}
}
```

### `Runner` — `src/Runner.php`

```php
declare(strict_types=1);

namespace CallCodingClis;

class Runner
{
    public function run(CommandSpec $spec): CompletedRun
    public function stream(CommandSpec $spec, callable $onEvent): CompletedRun
}
```

Follows the Python/Rust pattern: `run()` captures all output, `stream()` calls the callback with `("stdout", $data)` / `("stderr", $data)` after completion (non-streaming passthrough like Rust). The `stream()` method is a non-streaming passthrough — it calls `run()` internally and then fires the callback, matching the Rust and TypeScript behavior.

No executor injection for v1 (unlike Python/Rust). The Runner directly calls `proc_open`. This can be added later if needed for testing.

### `build_prompt_spec()` — `src/build_prompt_spec.php`

```php
declare(strict_types=1);

namespace CallCodingClis;

function build_prompt_spec(string $prompt): CommandSpec
```

Returns `CommandSpec` or throws `\InvalidArgumentException` on empty/whitespace input. Free function matches the Python/Rust convention.

## 3. Subprocess via `proc_open`

`Runner::run()` uses PHP's native `proc_open()` with `bypass_shell` to avoid shell interpolation (matching how Python `subprocess.run` and Rust `Command::new` pass argv directly):

```php
$cmd = $spec->argv;
if (($realOpenCode = getenv('CCC_REAL_OPENCODE')) !== false) {
    $cmd[0] = $realOpenCode;
}

$descriptorspec = [
    0 => ['pipe', 'r'],
    1 => ['pipe', 'w'],
    2 => ['pipe', 'w'],
];

$cwd = $spec->cwd;
$env = $spec->env;
$process = proc_open($cmd, $descriptorspec, $pipes, $cwd, $env, ['bypass_shell' => true]);
```

**`bypass_shell: true`** is critical. Without it, the binary name and arguments go through the shell, which mangles quoting and breaks contract test expectations. When `bypass_shell` is true, `$cmd` must be an array (not a string).

**Important**: With `bypass_shell: true` and `$env = []`, PHP will still pass `$_SERVER` or `$_ENV` environment depending on SAPI. To ensure clean env behavior, if `$spec->env` is non-empty, merge it onto `getenv()`:

```php
$mergedEnv = null; // null means "inherit current env" for proc_open
if ($spec->env !== []) {
    $mergedEnv = getenv();       // get all current env vars as array
    foreach ($spec->env as $k => $v) {
        $mergedEnv[$k] = $v;    // override with spec values
    }
}
```

Pass `$mergedEnv` as the `$env` parameter to `proc_open`. When `$mergedEnv` is `null`, proc_open inherits the current environment (no overrides needed).

### Execution steps:

1. Build `$cmd` array from `$spec->argv`. If `CCC_REAL_OPENCODE` env var is set, replace `$cmd[0]`.
2. Set up `$descriptorspec` with three pipes.
3. Call `proc_open($cmd, $descriptorspec, $pipes, $spec->cwd, $mergedEnv, ['bypass_shell' => true])`.
4. If `proc_open` returns `false`: return `CompletedRun` with `exitCode: 1`, `stderr: "failed to start {$spec->argv[0]}: proc_open failed\n"`.
5. Write `$spec->stdinText` to `$pipes[0]` (if non-null), then close `$pipes[0]`.
6. Read `$pipes[1]` and `$pipes[2]` into `$stdout` / `$stderr` via `stream_get_contents()`.
7. Close `$pipes[1]` and `$pipes[2]`.
8. Call `proc_close($process)` to get exit code. This returns the child's exit status, or `-1` on error.
9. Return `CompletedRun` with the captured output.

### Exit code handling:

`proc_close()` returns:
- The child process exit code on normal exit (0–255).
- `-1` if the process could not be terminated or `pcntl_wexitstatus` fails.

Map this like the C implementation:
```php
$rawExitCode = proc_close($process);
$exitCode = ($rawExitCode >= 0) ? $rawExitCode : 1;
```

## 4. `ccc` CLI as `bin/ccc`

```
#!/usr/bin/env php
<?php
declare(strict_types=1);

use CallCodingClis\build_prompt_spec;
use CallCodingClis\Runner;

require __DIR__ . '/../vendor/autoload.php';

$args = array_slice($argv, 1);
if (count($args) !== 1) {
    fwrite(STDERR, 'usage: ccc "<Prompt>"' . PHP_EOL);
    exit(1);
}

try {
    $spec = build_prompt_spec($args[0]);
} catch (\InvalidArgumentException $e) {
    fwrite(STDERR, $e->getMessage() . PHP_EOL);
    exit(1);
}

$result = (new Runner())->run($spec);
if ($result->stdout !== '') {
    fwrite(STDOUT, $result->stdout);
}
if ($result->stderr !== '') {
    fwrite(STDERR, $result->stderr);
}
exit($result->exitCode);
```

Must be executable (`chmod +x`). The shebang line allows direct invocation (`./bin/ccc`). For the cross-language contract tests, the invocation is `["php", "php/bin/ccc", PROMPT]` — the shebang is not required for that path but enables standalone use.

### `CCC_REAL_OPENCODE` env var

The CLI reads `CCC_REAL_OPENCODE` from the environment and uses it to override `argv[0]` in the `Runner`. This is handled inside `Runner::run()` — when the env var is set, `$spec->argv[0]` is replaced with its value before calling `proc_open`. This matches the C implementation (`c/src/ccc.c:48`).

## 5. Prompt Trimming & Empty Rejection

```php
function build_prompt_spec(string $prompt): CommandSpec
{
    $normalized = trim($prompt);
    if ($normalized === '') {
        throw new \InvalidArgumentException('prompt must not be empty');
    }
    return new CommandSpec(['opencode', 'run', $normalized]);
}
```

`trim()` handles leading/trailing whitespace. Empty/whitespace-only input (including `"   "`) triggers `InvalidArgumentException`. The error message matches all other implementations: `"prompt must not be empty"`.

The `InvalidArgumentException` is caught by `bin/ccc` and written to stderr followed by a newline (via `PHP_EOL`). The process exits with code 1.

## 6. Error Format: `argv[0]` Only

When `proc_open()` fails (binary not found, permissions, etc.), stderr must be:

```
failed to start <argv[0]>: <error_message>
```

Only the first element of `$spec->argv` appears in the message, not the full command line. This matches Python (`spec.argv[0]`) and Rust (`spec.argv.first()`).

## 7. Exit Code Forwarding

`bin/ccc` calls `exit($result->exitCode)` to forward the subprocess exit code verbatim. This matches all other implementations.

`Runner::run()` returns `proc_close()`'s return value directly as `$exitCode`, which is the child's wait status (same as Python's `returncode` and Rust's `status.code()`).

## 8. Test Strategy

### PHPUnit Tests — `php/tests/`

**Unit tests** (no subprocess):

| Test | Validates |
|------|-----------|
| `build_prompt_spec` with valid prompt | Returns `CommandSpec` with correct argv |
| `build_prompt_spec` with empty string | Throws `InvalidArgumentException` |
| `build_prompt_spec` with whitespace-only | Throws `InvalidArgumentException` |
| `build_prompt_spec` trims whitespace | Leading/trailing spaces stripped from argv[2] |

**Integration tests** (subprocess required):

| Test | Setup | Validates |
|------|-------|-----------|
| Happy path | `CCC_REAL_OPENCODE` pointing to stub | Exit 0, stdout matches `opencode run <prompt>\n` |
| Startup failure | Nonexistent binary | Exit 1, stderr contains `"failed to start"` |
| Exit code forwarding | Stub that exits with code 7 | Exit code 7 forwarded |
| Stdin forwarding | Stub that echoes stdin | stdin_text passed through |
| CWD forwarding | Stub that prints cwd | cwd respected |
| Env forwarding | Stub that prints env var | env overrides applied |

**`CCC_REAL_OPENCODE` env var**: The `Runner` must check `getenv('CCC_REAL_OPENCODE')` and, if set, replace `$spec->argv[0]` with that value. This is consistent with the C implementation and allows contract tests to inject a stub binary.

### Cross-Language Contract Tests

Add a PHP entry to `tests/test_ccc_contract.py`:

```python
self.assert_equal_output(
    subprocess.run(
        ["php", "php/bin/ccc", PROMPT],
        cwd=ROOT,
        env={**env, "CCC_REAL_OPENCODE": str(bin_dir / "opencode")},
        capture_output=True,
        text=True,
        check=False,
    )
)
```

This requires `php/bin/ccc` to be runnable directly (shebang line + autoload).

### PHPUnit Config — `php/phpunit.xml`

```xml
<phpunit bootstrap="vendor/autoload.php">
    <testsuites>
        <testsuite name="unit">
            <directory>tests/Unit</directory>
        </testsuite>
        <testsuite name="integration">
            <directory>tests/Integration</directory>
        </testsuite>
    </testsuites>
</phpunit>
```

## 9. PHP-Specific Considerations

### Composer Autoloading

PSR-4 mapping `CallCodingClis\` → `src/`. All classes in `src/` must be in the `CallCodingClis` namespace. `bin/ccc` requires the autoloader explicitly since it's invoked directly.

### Type Declarations

PHP 8.2+:
- All method parameters and return types declared (strict types)
- `declare(strict_types=1)` at top of every file
- `readonly` properties for immutable data objects (`CommandSpec`, `CompletedRun`)
- Union types where needed (`?string`, `string|int`)
- Named arguments used at call sites for clarity

### PHP 8.x Features Used

- **PHP 8.2 `readonly` classes/properties**: For `CommandSpec` and `CompletedRun`
- **PHP 8.0 named arguments**: Optional when calling constructors
- **PHP 8.0 union types**: Where applicable
- **PHP 7.4 `proc_open` bypass_shell**: Avoids shell interpolation of argv
- **PHP 8.0 match expression**: Could be used in CLI arg parsing (minor)
- **PHP 8.0 `str_contains`**: If needed in tests

### Target: PHP 8.2 minimum

Rationale: `readonly` properties for clean value objects without boilerplate. Widely available (Ubuntu 22.04+ ships 8.1, but 8.2+ is standard for new projects as of 2024+).

## 10. Parity Gaps (post-v1)

| Feature | Status in Plan | Notes |
|---------|---------------|-------|
| `build_prompt_spec` | Planned | Full parity |
| `Runner.run` | Planned | Full parity via `proc_open` |
| `Runner.stream` | Planned (non-streaming) | Passthrough after run, matches Rust |
| `ccc` CLI | Planned | Full parity |
| Prompt trimming | Planned | `trim()` |
| Empty prompt rejection | Planned | `\InvalidArgumentException` |
| Stdin/CWD/Env support | Planned | All passed to `proc_open` |
| Startup failure reporting | Planned | `"failed to start <argv[0]>"` format |
| Exit code forwarding | Planned | `exit($result->exitCode)` |
| `CCC_REAL_OPENCODE` test override | Planned | env var check in Runner |
| Contract test entry | Planned | Addition to `test_ccc_contract.py` |

### Known Deliberate Gaps (not in v1 scope)

| Feature | Why Deferred |
|---------|-------------|
| Real-time streaming | `proc_open` with non-blocking reads is possible but significantly more complex; Rust also uses non-streaming passthrough |
| Composer package publish | Package structure supports it, but no intent to publish to Packagist until requested |
| PHP extension (`ext-ffi` bindings) | Unnecessary; the library surface is trivial |
| `@alias`, `+0..+4`, `:provider:model` | Non-contract per `CCC_BEHAVIOR_CONTRACT.md` — all implementations defer these |

## File-by-File Implementation Order

1. `php/composer.json` — package definition, autoloading
2. `php/src/CommandSpec.php` — data class
3. `php/src/CompletedRun.php` — data class
4. `php/src/Runner.php` — subprocess execution with `proc_open`
5. `php/src/build_prompt_spec.php` — prompt normalization + spec builder
6. `php/bin/ccc` — CLI entry point
7. `php/tests/` — PHPUnit unit + integration tests
8. `tests/test_ccc_contract.py` — add PHP entries to cross-language tests

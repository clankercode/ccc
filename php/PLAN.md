# PHP Implementation Plan — call-coding-clis

## 1. Composer Package Structure

```
php/
├── composer.json
├── bin/
│   └── ccc              # CLI entry point (chmod +x, #!/usr/bin/env php)
└── src/
    ├── CommandSpec.php
    ├── CompletedRun.php
    ├── Runner.php
    └── build_prompt_spec.php
```

`composer.json` sketch:

- **name**: `call-coding-clis/php` (or `anomaly/call-coding-clis-php`)
- **type**: `library`
- **require**: `"php": ">=8.2"`
- **require-dev**: `"phpunit/phpunit": "^10|^11"`
- **autoload**: PSR-4 `CallCodingClis\\` → `src/`
- **bin**: `["bin/ccc"]`

No external runtime dependencies. `symfony/process` is not required — `proc_open` from the standard library is sufficient and avoids a dependency for such a thin wrapper.

## 2. Library API

### `CommandSpec` — `src/CommandSpec.php`

```php
class CommandSpec
{
    public function __construct(
        public readonly array $argv,
        public readonly ?string $stdinText = null,
        public readonly ?string $cwd = null,
        public readonly array $env = [],
    ) {}
}
```

Immutability via `readonly` properties (PHP 8.2). Builder-style optional methods (`withStdin`, `withCwd`, `withEnv`) are unnecessary given the small surface; named args suffice.

### `CompletedRun` — `src/CompletedRun.php`

```php
class CompletedRun
{
    public function __construct(
        public readonly array $argv,
        public readonly int $exitCode,
        public readonly string $stdout,
        public readonly string $stderr,
    ) {}
}
```

### `Runner` — `src/Runner.php`

```php
class Runner
{
    public function run(CommandSpec $spec): CompletedRun
    public function stream(CommandSpec $spec, callable $onEvent): CompletedRun
}
```

Follows the Python/Rust pattern: `run()` captures all output, `stream()` calls the callback with `("stdout", $data)` / `("stderr", $data)` after completion (non-streaming passthrough like Rust). Injectability is not strictly needed for v1 parity but can be added later via an optional executor callable.

### `build_prompt_spec()` — `src/build_prompt_spec.php`

```php
function build_prompt_spec(string $prompt): CommandSpec
```

Returns `CommandSpec` or throws `\InvalidArgumentException` on empty/whitespace input. Namespace: `CallCodingClis\build_prompt_spec` (or a class method; free function matches the Python/Rust convention).

## 3. Subprocess via `proc_open`

`Runner::run()` will use PHP's native `proc_open()`:

1. Build a `descriptorspec` array: `0 => ["pipe", "r"]`, `1 => ["pipe", "w"]`, `2 => ["pipe", "w"]`.
2. Call `proc_open($cmd, $descriptorspec, $pipes, $spec->cwd, $mergedEnv)`.
   - `$cmd` is `$spec->argv[0]` with args passed via `$spec->argv` escaped with `escapeshellarg()` — **or** use the `bypass_shell: true` option (PHP 7.4+) to pass argv directly as an array to `proc_open` without shell interpolation, matching how Rust/Python do it.
3. Write `$spec->stdinText` to `$pipes[0]`, close it.
4. Read `$pipes[1]` and `$pipes[2]` into `$stdout` / `$stderr`.
5. Close remaining pipes, call `proc_close()` to get exit code.
6. On `proc_open` failure (returns `false`): return `CompletedRun` with `exitCode: 1`, `stderr: "failed to start {$spec->argv[0]}: <error>"`.

Key: `bypass_shell: true` is critical for correct argv passing. Without it, the binary name and arguments go through the shell, which would mangle quoting and break the contract test expectations.

## 4. `ccc` CLI as `bin/ccc`

```
#!/usr/bin/env php
<?php
require __DIR__ . '/../vendor/autoload.php';

use CallCodingClis\build_prompt_spec;
use CallCodingClis\Runner;

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

Must be executable (`chmod +x`). When installed via `composer install`, Composer handles this automatically.

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

`trim()` handles leading/trailing whitespace. Empty/whitespace-only input (including `"   "`) triggers `InvalidArgumentException`. The error message matches other implementations: `"prompt must not be empty"`.

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

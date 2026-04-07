# Ruby Implementation Plan: call-coding-clis

## 1. Project Structure

```
ruby/
  Gemfile
  call_coding_clis.gemspec
  Rakefile
  lib/
    call_coding_clis.rb          # top-level require, pulls in submodules
    call_coding_clis/
      command_spec.rb            # CommandSpec (Struct)
      completed_run.rb           # CompletedRun (Struct)
      runner.rb                  # Runner class
      prompt_spec.rb             # build_prompt_spec
      version.rb                 # gem version constant
  bin/
    ccc                          # CLI entry point (chmod +x)
  test/
    test_command_spec.rb
    test_completed_run.rb
    test_runner.rb
    test_prompt_spec.rb
    test_ccc_cli.rb
```

No Bundler binstub -- `bin/ccc` is a thin shell script that sets up load paths and calls the CLI module directly, matching the convention used by other language implementations here (single executable, no build step).

## 2. Library API

### CommandSpec (`lib/call_coding_clis/command_spec.rb`)

```ruby
CommandSpec = Struct.new(:argv, :stdin_text, :cwd, :env, keyword_init: true) do
  def initialize(argv:, stdin_text: nil, cwd: nil, env: {})
    super
  end
end
```

- `argv`: `Array<String>` -- required
- `stdin_text`: `String | nil`
- `cwd`: `String | nil`
- `env`: `Hash<String, String>`

Using `Struct` with `keyword_init` gives us `#==`, `#inspect`, and `#to_h` for free, and avoids the ceremony of a full class.

### CompletedRun (`lib/call_coding_clis/completed_run.rb`)

```ruby
CompletedRun = Struct.new(:argv, :exit_code, :stdout, :stderr, keyword_init: true)
```

- `argv`: `Array<String>` -- snapshot of the spec's argv at invocation
- `exit_code`: `Integer`
- `stdout`: `String`
- `stderr`: `String`

### Runner (`lib/call_coding_clis/runner.rb`)

```ruby
class Runner
  def initialize(executor: nil, stream_executor: nil)
    @executor = executor || method(:default_run)
    @stream_executor = stream_executor || method(:default_stream)
  end

  def run(spec)           # -> CompletedRun
  def stream(spec) { |channel, text| ... }  # -> CompletedRun
end
```

Constructor accepts optional executor/strategy callables for testability, matching the Python and Rust patterns. The `stream` method yields `(channel, text)` to a block -- this is the most idiomatic Ruby pattern and avoids needing a separate callback object.

### build_prompt_spec (`lib/call_coding_clis/prompt_spec.rb`)

```ruby
module CallCodingClis
  def self.build_prompt_spec(prompt)
    normalized = prompt.strip
    raise ArgumentError, "prompt must not be empty" if normalized.empty?
    CommandSpec.new(argv: ["opencode", "run", normalized])
  end
end
```

Returns `CommandSpec` or raises `ArgumentError` (Ruby's natural choice; mirrors the ValueError/Result patterns in other impls).

## 3. Subprocess Execution

Use `Open3.capture3` for `run` and `Open3.popen3` for `stream`:

**run** (via `Open3.capture3`):
- `capture3(*spec.argv, stdin_data: spec.stdin_text, chdir: spec.cwd, env: merged_env)`
- Returns `[stdout, stderr, status]`. `status.exitstatus` gives the exit code.
- Wrap in `rescue Errno::ENOENT, Errno::EACCES` to produce the `"failed to start <argv[0]>: <message>"` error.

**stream** (via `Open3.popen3`):
- `popen3(*spec.argv, chdir:, env:)` yields `stdin_w, stdout_r, stderr_r, wait_thr`
- Write `spec.stdin_text` to `stdin_w` if present, then close.
- Read from stdout_r/stderr_r in a loop (or use threads) yielding `"stdout"/"stderr"` + chunk to the block.
- `wait_thr.value.exitstatus` gives exit code.
- Wrap in same `rescue` for startup failures.

`Open3` is stdlib -- no gem dependencies needed for core functionality.

## 4. `ccc` CLI (`bin/ccc`)

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/call_coding_clis"

args = ARGV

if args.length != 1
  warn 'usage: ccc "<Prompt>"'
  exit 1
end

begin
  spec = CallCodingClis.build_prompt_spec(args[0])
rescue ArgumentError => e
  warn e.message
  exit 1
end

# Support CCC_REAL_OPENCODE override (for contract tests)
if (real = ENV["CCC_REAL_OPENCODE"])
  spec.argv[0] = real
end

result = Runner.new.stream(spec) do |channel, text|
  case channel
  when "stdout" then $stdout.write(text)
  when "stderr" then $stderr.write(text)
  end
end

exit(result.exit_code)
```

Key decisions:
- Uses `stream` path (like TypeScript) so output flows in real-time.
- `warn` writes to stderr without trailing newline issues.
- `exit(result.exit_code)` forwards the subprocess exit code directly.
- `CCC_REAL_OPENCODE` env var support for testing (same as C implementation).

## 5. Prompt Trimming & Empty Rejection

- `prompt.strip` handles leading/trailing whitespace (built-in `String#strip`).
- `.empty?` check after strip rejects empty and whitespace-only prompts.
- Error message: `"prompt must not be empty"` on stderr, exit 1.
- This matches all other implementations exactly.

## 6. Error Format

Startup failures produce: `"failed to start <argv[0]>: <error_message>"`

Example: `"failed to start opencode: No such file or directory"`

- Only `argv[0]`, never the full argv array.
- Trailing newline included (`\n`) to match other implementations.
- Exit code 1 for startup failures.

## 7. Exit Code Forwarding

- `result.exit_code` comes from `Process::Status#exitstatus`.
- Signal kills (`exitstatus` returns `nil`) should map to exit code 1, matching Rust's `unwrap_or(1)`.
- CLI calls `exit(result.exit_code)` to forward exactly.

## 8. Test Strategy

**Framework: minitest** (stdlib, zero dependencies, matches the project's lightweight ethos).

Tests live in `ruby/test/`:

| Test file | Covers |
|-----------|--------|
| `test_command_spec.rb` | Construction, defaults, keyword init |
| `test_completed_run.rb` | Construction, field access |
| `test_prompt_spec.rb` | Trimming, empty rejection, whitespace-only, normal prompt |
| `test_runner.rb` | Run with fake executor, stream with block, startup failure (Errno), exit code forwarding, env merging |
| `test_ccc_cli.rb` | Arg count validation, empty prompt, happy path via subprocess invocation of bin/ccc |

**CCC_REAL_OPENCODE override**: Tests that invoke the actual CLI use a temporary fake binary (same pattern as `test_ccc_contract.py`). The `bin/ccc` script reads `CCC_REAL_OPENCODE` and swaps `argv[0]`.

**Run tests**: `ruby -Ilib -Itest test/test_*.rb` or a simple Rake task.

## 9. Ruby-Specific Considerations

### Blocks for streaming
Ruby blocks (`yield`) are the natural callback mechanism. `stream` yields `("stdout", chunk)` or `("stderr", chunk)`. Callers can also pass a proc: `runner.stream(spec, &handler)`.

### Dynamic typing
No type annotations needed. The contract is enforced by duck typing and the test suite. If desired later, `type_check` or `rbs` could add optional static checks, but they are not required for parity.

### Gem packaging
Minimal gemspec:
- Name: `call_coding_clis`
- Files: `lib/**/*`, `bin/*`
- No runtime dependencies (stdlib only)
- Development deps: `minitest`, `rake`
- `executables: ["ccc"]`

The gem is primarily for packaging/distribution; the implementation works without `gem install` via direct `ruby bin/ccc`.

### Frozen string literals
All files use `# frozen_string_literal: true` for consistency and minor perf benefit.

### Encoding
`String#strip`, `Open3` -- all default to UTF-8 in modern Ruby. No special handling needed for the prompt use case.

### Thread safety for stream
If true line-by-line streaming is needed, use two threads reading stdout_r and stderr_r concurrently (avoiding deadlock if the child's buffers fill up). For simplicity, a single-threaded `select` loop or `IO.select` works. Start simple with sequential reads since opencode may buffer its own output.

## 10. Parity Gaps to Watch For

| Area | Risk | Mitigation |
|------|------|------------|
| `CCC_RUNNER_PREFIX_JSON` | TypeScript supports a JSON env var to override the runner prefix. Other impls do not. **Skip for now** -- not in shared contract. | Only implement if it becomes contract. |
| Streaming fidelity | Rust's `stream` is currently non-streaming (runs then yields). Ruby should match TypeScript's real streaming approach. | Use `Open3.popen3` with IO.select for true streaming. |
| Env merging | Ensure `spec.env` is merged *into* the parent env (not replaced), matching all other impls. | `ENV.to_h.merge(spec.env)` passed to `Open3`. |
| Signal exit codes | `exitstatus` returns `nil` on signal kills. Must map to 1. | `status.exitstatus \|\| 1` |
| Newline in error messages | Other impls include `\n` at end of error messages. | Ensure `"...\n"` format. |
| Contract test integration | The shared `tests/test_ccc_contract.py` does not yet include Ruby. | Add a subprocess invocation of `ruby ruby/bin/ccc` to the contract test after implementation. |
| No `require_relative` in library | Library files should use `require_relative` only within the gem's own files. `bin/ccc` can use it for bootstrap. | Keep `lib/call_coding_clis.rb` as the single entry point; it requires submodules. |

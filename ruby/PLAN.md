# Ruby Implementation Plan: call-coding-clis

## 1. Project Structure

```
ruby/
  Gemfile
  Rakefile
  call_coding_clis.gemspec
  lib/
    call_coding_clis.rb            # top-level require, pulls in submodules
    call_coding_clis/
      version.rb                   # gem version constant
      command_spec.rb              # CommandSpec (Struct)
      completed_run.rb             # CompletedRun (Struct)
      runner.rb                    # Runner class
      prompt_spec.rb               # build_prompt_spec
  bin/
    ccc                            # CLI entry point (chmod +x)
  test/
    test_command_spec.rb
    test_completed_run.rb
    test_runner.rb
    test_prompt_spec.rb
    test_ccc_cli.rb
```

No Bundler binstub -- `bin/ccc` is a thin script that sets up load paths and calls the CLI module directly, matching the convention used by other language implementations here (single executable, no build step).

## 2. Library API

### Top-level require (`lib/call_coding_clis.rb`)

```ruby
# frozen_string_literal: true

require_relative "call_coding_clis/version"
require_relative "call_coding_clis/command_spec"
require_relative "call_coding_clis/completed_run"
require_relative "call_coding_clis/runner"
require_relative "call_coding_clis/prompt_spec"
```

### CommandSpec (`lib/call_coding_clis/command_spec.rb`)

```ruby
# frozen_string_literal: true

module CallCodingClis
  CommandSpec = Struct.new(:argv, :stdin_text, :cwd, :env, keyword_init: true) do
    def initialize(argv:, stdin_text: nil, cwd: nil, env: {})
      super
    end
  end
end
```

- `argv`: `Array<String>` -- required
- `stdin_text`: `String | nil`
- `cwd`: `String | nil`
- `env`: `Hash<String, String>`

Using `Struct` with `keyword_init` gives us `#==`, `#inspect`, and `#to_h` for free, and avoids the ceremony of a full class. Everything lives under the `CallCodingClis` module namespace for consistency.

### CompletedRun (`lib/call_coding_clis/completed_run.rb`)

```ruby
# frozen_string_literal: true

module CallCodingClis
  CompletedRun = Struct.new(:argv, :exit_code, :stdout, :stderr, keyword_init: true)
end
```

- `argv`: `Array<String>` -- snapshot of the spec's argv at invocation (use `spec.argv.dup`)
- `exit_code`: `Integer`
- `stdout`: `String`
- `stderr`: `String`

**Important**: The `argv` field must be a copy (`dup`), not a shared reference to `spec.argv`. This matches Python's `list(spec.argv)` and Rust's `spec.argv` (which is moved).

### Runner (`lib/call_coding_clis/runner.rb`)

```ruby
# frozen_string_literal: true

require "open3"

module CallCodingClis
  class Runner
    def initialize(executor: nil, stream_executor: nil)
      @executor = executor || method(:default_run)
      @stream_executor = stream_executor || method(:default_stream)
    end

    def run(spec)
      @executor.call(spec)
    end

    def stream(spec, &block)
      @stream_executor.call(spec, block)
    end

    private

    def merged_env(overrides)
      ENV.to_h.merge(overrides)
    end
  end
end
```

Constructor accepts optional executor/strategy callables for testability, matching the Python and Rust patterns. The `stream` method accepts a block `|channel, text|` -- this is the most idiomatic Ruby pattern and avoids needing a separate callback object.

### build_prompt_spec (`lib/call_coding_clis/prompt_spec.rb`)

```ruby
# frozen_string_literal: true

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

Use `Open3.capture3` for `run` and `Open3.popen3` for `stream`. Both are stdlib -- no gem dependencies needed.

### run (via `Open3.capture3`)

```ruby
def default_run(spec)
  stdout, stderr, status = Open3.capture3(
    *spec.argv,
    stdin_data: spec.stdin_text,
    chdir: spec.cwd,
    env: merged_env(spec.env)
  )
  CompletedRun.new(
    argv: spec.argv.dup,
    exit_code: status.exitstatus || 1,
    stdout: stdout,
    stderr: stderr
  )
rescue Errno::ENOENT, Errno::EACCES => e
  CompletedRun.new(
    argv: spec.argv.dup,
    exit_code: 1,
    stdout: "",
    stderr: "failed to start #{spec.argv[0]}: #{e.message}\n"
  )
end
```

Key details:
- `Open3.capture3(*spec.argv)` splats the array so the subprocess receives separate args (no shell interpolation).
- `stdin_data:` passes stdin text (nil means no stdin, child sees EOF immediately).
- `chdir:` sets working directory. Supported since Ruby 2.6.
- `status.exitstatus || 1` maps signal kills (where `exitstatus` returns `nil`) to exit code 1, matching Rust's `unwrap_or(1)`.
- `e.message` for `Errno::ENOENT` produces `"No such file or directory - <argv[0]>"`. This differs slightly from Python's `"No such file or directory: '<argv[0]>'"` but the error format string `"failed to start <argv[0]>: <error>\n"` is consistent.

### stream (via `Open3.popen3` with threads)

```ruby
def default_stream(spec, block)
  stdin_w, stdout_r, stderr_r, wait_thr = Open3.popen3(
    *spec.argv,
    chdir: spec.cwd,
    env: merged_env(spec.env)
  )
  stdin_w.close

  stdout_buf = Thread.new { stdout_r.read }
  stderr_buf = Thread.new { stderr_r.read }

  stdout_text = stdout_buf.value
  stderr_text = stderr_buf.value

  stdout_r.close
  stderr_r.close

  block&.call("stdout", stdout_text) if stdout_text && !stdout_text.empty?
  block&.call("stderr", stderr_text) if stderr_text && !stderr_text.empty?

  CompletedRun.new(
    argv: spec.argv.dup,
    exit_code: wait_thr.value.exitstatus || 1,
    stdout: stdout_text.to_s,
    stderr: stderr_text.to_s
  )
rescue Errno::ENOENT, Errno::EACCES => e
  block&.call("stderr", "failed to start #{spec.argv[0]}: #{e.message}\n")
  CompletedRun.new(
    argv: spec.argv.dup,
    exit_code: 1,
    stdout: "",
    stderr: "failed to start #{spec.argv[0]}: #{e.message}\n"
  )
ensure
  [stdin_w, stdout_r, stderr_r].each { |io| io&.close }
end
```

**Why threads, not sequential reads or `IO.select`:** Reading stdout and stderr sequentially from a child process can deadlock if the child writes enough to fill one pipe buffer while the parent is blocked reading the other. Two threads (one per pipe) is the standard Ruby idiom and avoids this entirely. The Ruby stdlib `Open3.capture3` itself uses this pattern internally.

**Why close stdin immediately:** The child may block waiting for stdin EOF. Closing `stdin_w` signals EOF so the child can proceed regardless of whether `spec.stdin_text` was provided. If stdin support is needed, write to `stdin_w` before closing.

**Future streaming improvement:** The above collects all output then yields. For true incremental streaming (like Python's `Popen` + `communicate`), use a thread-based read loop with chunked `IO.readpartial` calls. This is a performance optimization -- not required for contract compliance.

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

if (real = ENV["CCC_REAL_OPENCODE"])
  spec = CallCodingClis::CommandSpec.new(
    argv: [real, *spec.argv[1..]],
    stdin_text: spec.stdin_text,
    cwd: spec.cwd,
    env: spec.env
  )
end

result = CallCodingClis::Runner.new.stream(spec) do |channel, text|
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
- `CCC_REAL_OPENCODE` support: creates a **new** `CommandSpec` with `argv[0]` replaced instead of mutating the original. This is cleaner and avoids shared-reference bugs.
- All class references are fully qualified (`CallCodingClis::Runner`, `CallCodingClis::CommandSpec`).

## 5. Prompt Trimming & Empty Rejection

- `prompt.strip` handles leading/trailing whitespace (built-in `String#strip`).
- `.empty?` check after strip rejects empty and whitespace-only prompts.
- Error message: `"prompt must not be empty"` on stderr, exit 1.
- This matches all other implementations exactly.

## 6. Error Format

Startup failures produce: `"failed to start <argv[0]>: <error_message>\n"`

Example: `"failed to start opencode: No such file or directory - opencode\n"`

- Only `argv[0]`, never the full argv array.
- Trailing newline included (`\n`) to match other implementations.
- Exit code 1 for startup failures.
- Ruby's `Errno::ENOENT#message` includes the program name (`"No such file or directory - opencode"`). The contract test only checks that stderr contains `"failed to start"`, so the minor format difference is acceptable.

## 7. Exit Code Forwarding

- `result.exit_code` comes from `Process::Status#exitstatus`.
- Signal kills (`exitstatus` returns `nil`) map to exit code 1: `status.exitstatus || 1`.
- CLI calls `exit(result.exit_code)` to forward exactly.

## 8. Gem Packaging

### Gemfile

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec
```

### `call_coding_clis.gemspec`

```ruby
# frozen_string_literal: true

require_relative "lib/call_coding_clis/version"

Gem::Specification.new do |spec|
  spec.name          = "call_coding_clis"
  spec.version       = CallCodingClis::VERSION
  spec.summary       = "Library and CLI for invoking coding CLIs as subprocesses"
  spec.authors       = ["call-coding-clis contributors"]
  spec.license       = "Unlicense"

  spec.files         = Dir.glob("lib/**/*") + Dir.glob("bin/*")
  spec.executables   = ["ccc"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.6"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
```

Key details:
- `spec.files` uses `Dir.glob` to include only `lib/` and `bin/` -- excludes tests, Gemfile, gemspec, etc.
- `spec.executables` ensures `bin/ccc` is installed on `PATH` when the gem is installed.
- `required_ruby_version >= 2.6` because `Open3.capture3(*args, chdir:)` requires 2.6+.
- Zero runtime dependencies -- everything is stdlib (`open3`, `json` if needed later).

### Version (`lib/call_coding_clis/version.rb`)

```ruby
# frozen_string_literal: true

module CallCodingClis
  VERSION = "0.1.0"
end
```

## 9. Rakefile

```ruby
# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "lib"
  t.libs << "test"
  t.test_files = FileList["test/test_*.rb"]
end

task default: :test
```

## 10. Build Instructions

### Running without gem install (development mode)

```sh
cd ruby
ruby bin/ccc "Fix the failing tests"
```

### Running tests

```sh
cd ruby
ruby -Ilib -Itest test/test_command_spec.rb
ruby -Ilib -Itest test/test_completed_run.rb
ruby -Ilib -Itest test/test_runner.rb
ruby -Ilib -Itest test/test_prompt_spec.rb
ruby -Ilib -Itest test/test_ccc_cli.rb

# Or all at once:
ruby -Ilib -Itest test/test_*.rb

# Or via Rake:
rake test
```

### Building and installing the gem

```sh
cd ruby
gem build call_coding_clis.gemspec
gem install call_coding_clis-0.1.0.gem
ccc "Fix the failing tests"
```

### Uninstalling

```sh
gem uninstall call_coding_clis
```

## 11. CI Notes

### Cross-language contract test registration

After implementation, register Ruby in `tests/test_ccc_contract.py` by adding a subprocess invocation to each test method. The pattern follows the existing C registration:

```python
self.assert_equal_output(
    subprocess.run(
        ["ruby", "ruby/bin/ccc", PROMPT],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
)
```

This must be added in all four test methods:
1. `test_cross_language_ccc_happy_path`
2. `test_cross_language_ccc_rejects_empty_prompt`
3. `test_cross_language_ccc_requires_one_prompt_argument`
4. `test_cross_language_ccc_rejects_whitespace_only_prompt`

No build step is required (Ruby interprets directly), unlike C which needs `make` first.

### CI pipeline

Ruby requires no compilation. Ensure the CI environment has Ruby >= 2.6 installed. The contract test runner (`python3 -m pytest tests/test_ccc_contract.py`) will cover Ruby once registered.

### Optional CI job for Ruby-specific tests

```yaml
- name: Ruby tests
  run: |
    cd ruby
    ruby -Ilib -Itest test/test_*.rb
```

## 12. Test Strategy

**Framework: minitest** (stdlib, zero runtime dependencies, matches the project's lightweight ethos).

Tests live in `ruby/test/`:

| Test file | Covers |
|-----------|--------|
| `test_command_spec.rb` | Construction, defaults, keyword init, `argv` field types |
| `test_completed_run.rb` | Construction, field access, equality semantics from Struct |
| `test_prompt_spec.rb` | Trimming, empty rejection, whitespace-only, normal prompt, returns correct argv |
| `test_runner.rb` | Run with fake executor, stream with block, startup failure (Errno), exit code forwarding (`nil` -> 1), env merging, argv snapshot isolation |
| `test_ccc_cli.rb` | Arg count validation, empty prompt, whitespace prompt, happy path via subprocess invocation of `bin/ccc` using a fake `opencode` stub |

### Fake executor pattern for `test_runner.rb`

```ruby
def test_run_with_fake_executor
  fake_spec = CallCodingClis::CommandSpec.new(argv: ["echo", "hello"])
  fake_result = CallCodingClis::CompletedRun.new(
    argv: ["echo", "hello"],
    exit_code: 0,
    stdout: "hello\n",
    stderr: ""
  )
  runner = CallCodingClis::Runner.new(
    executor: ->(_spec) { fake_result }
  )
  result = runner.run(fake_spec)
  assert_equal 0, result.exit_code
  assert_equal "hello\n", result.stdout
end
```

### CLI test pattern for `test_ccc_cli.rb`

```ruby
def test_ccc_cli_happy_path
  Dir.mktmpdir do |tmp|
    stub = File.join(tmp, "opencode")
    File.write(stub, <<~SH)
      #!/bin/sh
      if [ "$1" != "run" ]; then exit 9; fi
      shift
      printf 'opencode run %s\\n' "$1"
    SH
    File.chmod(0o755, stub)

    env = { "PATH" => "#{tmp}:#{ENV['PATH']}" }
    output = IO.popen(["ruby", "bin/ccc", "Fix the failing tests"], err: [:child, :out], chdir: __dir__ + "/..", env: env)
    assert_equal "opencode run Fix the failing tests\n", output.read
    assert $?.success?
  end
end
```

### `CCC_REAL_OPENCODE` override test

Tests that invoke the actual CLI use a temporary fake binary (same pattern as `test_ccc_contract.py`). The `bin/ccc` script reads `CCC_REAL_OPENCODE` and swaps `argv[0]`.

## 13. Ruby-Specific Considerations

### Blocks for streaming
Ruby blocks (`yield`) are the natural callback mechanism. `stream` yields `("stdout", chunk)` or `("stderr", chunk)`. Callers can also pass a proc: `runner.stream(spec, &handler)`.

### Dynamic typing
No type annotations needed. The contract is enforced by duck typing and the test suite. If desired later, `rbs` (Ruby Signature files, bundled with Ruby 3.0+) could add optional static checks, but they are not required for parity.

### Frozen string literals
All files use `# frozen_string_literal: true` for consistency and minor perf benefit.

### Encoding
`String#strip`, `Open3` -- all default to UTF-8 in modern Ruby. No special handling needed for the prompt use case.

### Thread safety for stream
Two threads reading stdout_r and stderr_r concurrently avoids deadlock if the child's buffers fill up. This is the standard Ruby pattern -- `Open3.capture3` itself uses it internally.

## 14. Parity Gaps to Watch For

| Area | Risk | Mitigation |
|------|------|------------|
| `CCC_RUNNER_PREFIX_JSON` | TypeScript supports a JSON env var to override the runner prefix. Other impls do not. **Skip** -- not in shared contract. | Only implement if it becomes contract. |
| Streaming fidelity | Ruby's `stream` collects output then yields (matching Rust's current behavior). True incremental streaming would need `IO.readpartial` in a loop. | Current approach is contract-compliant. Optimize later if needed. |
| Env merging | Ensure `spec.env` is merged *into* the parent env (not replaced), matching all other impls. | `ENV.to_h.merge(spec.env)` passed to `Open3`. |
| Signal exit codes | `exitstatus` returns `nil` on signal kills. Must map to 1. | `status.exitstatus \|\| 1` |
| Newline in error messages | Other impls include `\n` at end of error messages. | Ensure `"...\n"` format in all error strings. |
| Contract test integration | The shared `tests/test_ccc_contract.py` does not yet include Ruby. | Add a subprocess invocation of `ruby ruby/bin/ccc` to each contract test method after implementation. |
| `Errno` message format | Ruby's `Errno::ENOENT#message` includes the program name, unlike Python/OS errno. | Acceptable: contract test only checks for `"failed to start"` substring. |
| `$LOAD_PATH` in bin/ccc | When running via `ruby bin/ccc`, `require_relative` works. When installed as a gem, Bundler/RubyGems handles load paths. | Use `require_relative` in `bin/ccc` for simplicity. No `$LOAD_PATH` manipulation needed. |
| Struct field mutation | Ruby `Struct` fields are mutable by default. Callers could mutate `spec.argv` after passing to Runner. | Runner always calls `spec.argv.dup` before storing in CompletedRun. Consider `Struct.new(...)` with no mutation risk since we don't expose mutating APIs. |

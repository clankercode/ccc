# Perl Implementation Plan

## 1. CPAN Distribution Structure

```
perl/
├── Makefile.PL
├── MANIFEST
├── lib/
│   └── Call/
│       ├── Coding/
│       │   └── Clis.pm          # re-exports build_prompt_spec, CommandSpec, CompletedRun, Runner
│       ├── Coding/
│       │   └── Clis/
│       │       ├── CommandSpec.pm
│       │       ├── CompletedRun.pm
│       │       └── Runner.pm
│       └── Coding.pm
├── bin/
│   └── ccc
└── t/
    ├── 01_build_prompt_spec.t
    ├── 02_runner.t
    ├── 03_cli.t
    └── 04_ccc_binary.t
```

Namespace: `Call::Coding::Clis`. The `Makefile.PL` declares the distribution name, dependencies, and installs `bin/ccc`. `MANIFEST` lists all shipped files.

**Dependencies (core-only preferred):**
- `IPC::Open3` (core) — subprocess execution with stdout/stderr capture
- `Symbol` (core) — gensym for stdin pipe handle
- `Test::More` (core) — testing
- No non-core CPAN deps required for the minimal implementation

**Optional upgrade path:** `IPC::Run` provides cleaner API for streaming, but `IPC::Open3` is core and sufficient for `run()`. Decision: use `IPC::Open3` for `run()`, accept `IPC::Run` as an optional dep for a future streaming improvement.

## 2. Library API

### `Call::Coding::Clis::CommandSpec`

Blessed hashref with accessor methods:

```perl
package Call::Coding::Clis::CommandSpec;

sub new {
    my ($class, %args) = @_;
    # %args: argv (required, arrayref), stdin_text, cwd, env (hashref)
    return bless \%args, $class;
}

sub argv       { $_[0]->{argv} }
sub stdin_text { $_[0]->{stdin_text} }
sub cwd        { $_[0]->{cwd} }
sub env        { $_[0]->{env} // {} }
```

Follows the Python dataclass / Rust struct pattern. Plain hashref, no Moose/Moo — keeps the dependency footprint at zero.

### `Call::Coding::Clis::CompletedRun`

```perl
package Call::Coding::Clis::CompletedRun;

sub new {
    my ($class, %args) = @_;
    # %args: argv, exit_code, stdout, stderr
    return bless \%args, $class;
}

sub argv      { $_[0]->{argv} }
sub exit_code { $_[0]->{exit_code} }
sub stdout    { $_[0]->{stdout} }
sub stderr    { $_[0]->{stderr} }
```

### `Call::Coding::Clis::Runner`

Constructor accepts optional `executor` coderef (mirrors Python's injectable executor pattern for testability):

```perl
package Call::Coding::Clis::Runner;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;
    $self->{executor} = $opts{executor} // sub { _default_run(@_) };
    return $self;
}

sub run {
    my ($self, $spec) = @_;
    return $self->{executor}->($spec);
}

sub stream {
    my ($self, $spec, $on_event) = @_;
    # Delegates to run() for now, then fires callbacks.
    # Matches Rust's current non-streaming stream() behavior.
    my $result = $self->run($spec);
    $on_event->('stdout', $result->stdout) if length $result->stdout;
    $on_event->('stderr', $result->stderr) if length $result->stderr;
    return $result;
}
```

### `Call::Coding::Clis::build_prompt_spec`

```perl
sub build_prompt_spec {
    my ($prompt) = @_;
    $prompt = '' unless defined $prompt;
    my $trimmed = $prompt;
    $trimmed =~ s/^\s+//;
    $trimmed =~ s/\s+$//;
    die "prompt must not be empty\n" unless length $trimmed;
    return Call::Coding::Clis::CommandSpec->new(
        argv => ['opencode', 'run', $trimmed],
    );
}
```

Exported by default from `Call::Coding::Clis`.

### `Call::Coding::Clis` (top-level facade)

Uses `Exporter` (core). Exports: `build_prompt_spec`. Also provides access to `CommandSpec`, `CompletedRun`, `Runner` via package names.

## 3. Subprocess Execution (`IPC::Open3`)

`_default_run` in `Runner`:

```perl
use IPC::Open3;
use Symbol 'gensym';

sub _default_run {
    my ($spec) = @_;
    my @argv = @{$spec->argv};
    my $argv0 = $argv[0];

    local %ENV = (%ENV, %{$spec->env});

    my ($stdin_w, $stdout_r, $stderr_r);
    $stderr_r = gensym;

    eval {
        my $pid = open3($stdin_w, $stdout_r, $stderr_r, @argv);
        close $stdin_w;
        if (defined $spec->stdin_text) {
            # Would need to write before close — restructure:
            # Use a pipe, write, then close.
        }
        my $stdout = do { local $/; <$stdout_r> };
        my $stderr = do { local $/; <$stderr_r> };
        waitpid($pid, 0);
        my $exit_code = $? >> 8;
        $stdout //= '';
        $stderr //= '';
        return Call::Coding::Clis::CompletedRun->new(
            argv      => \@argv,
            exit_code => $exit_code,
            stdout    => $stdout,
            stderr    => $stderr,
        );
    };
    if ($@) {
        return Call::Coding::Clis::CompletedRun->new(
            argv      => \@argv,
            exit_code => 1,
            stdout    => '',
            stderr    => "failed to start $argv0: $@\n",
        );
    }
}
```

**Key detail:** `IPC::Open3` throws on exec failure (ENOENT, permission denied). The `$@` message contains the OS error. The error format must be `"failed to start <argv[0]>: <error>"` per contract. We extract `$argv[0]` from `spec->argv->[0]` and interpolate `$@` as the error detail.

**stdin handling:** If `spec->stdin_text` is defined, write it to `$stdin_w` before closing. This matches all other implementations.

**env handling:** Merge `spec->env` overrides into `%ENV` inside a `local` block so parent process env is preserved.

**`CCC_REAL_OPENCODE` support:** Not needed inside the library. The CLI binary reads `$ENV{CCC_REAL_OPENCODE}` and, if set, replaces `opencode` in the argv of the spec returned by `build_prompt_spec`. This keeps the library clean.

## 4. `bin/ccc` CLI

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use Call::Coding::Clis qw(build_prompt_spec);
use Call::Coding::Clis::Runner;

my @args = @ARGV;

if (@args != 1) {
    print STDERR 'usage: ccc "<Prompt>"', "\n";
    exit 1;
}

my $spec = eval { build_prompt_spec($args[0]) };
if ($@) {
    print STDERR $@;
    exit 1;
}

my $runner = Call::Coding::Clis::Runner->new;

# CCC_REAL_OPENCODE override
if ($ENV{CCC_REAL_OPENCODE}) {
    $spec->{argv}[0] = $ENV{CCC_REAL_OPENCODE};
}

my $result = $runner->run($spec);
print $result->stdout if length $result->stdout;
print STDERR $result->stderr if length $result->stderr;
exit($result->exit_code);
```

The `FindBin` + `lib` approach allows running from the source tree without installing. `Makefile.PL` will also install `bin/ccc` properly.

## 5. Prompt Trimming and Empty Rejection

Implemented in `build_prompt_spec` (section 2). Uses `s/^\s+//` / `s/\s+$//` for trimming. Dies with `"prompt must not be empty\n"` if the trimmed result has zero length.

The CLI catches this via `eval { ... }; if ($@) { ... }` and writes `$@` to stderr, exiting 1.

This matches Python's `ValueError`, Rust's `Err`, and TypeScript's `throw`.

## 6. Error Format: `argv[0]` Only

The contract specifies: `"failed to start <argv[0]>: <error>"`.

In the `_default_run` function, on `open3` failure, we format:

```perl
stderr => "failed to start $argv[0]: $@\n"
```

Where `$argv[0]` is `$spec->argv->[0]`. This matches Python (`spec.argv[0]`), Rust (`spec.argv.first()`), and TypeScript (`command`).

**Perl nuance:** `$@` from `IPC::Open3` may include a trailing newline or may not. We should chomp it and add our own `\n` for consistency:

```perl
(my $err = $@) =~ s/\s+$//;
stderr => "failed to start $argv0: $err\n",
```

## 7. Exit Code Forwarding

The CLI uses `exit($result->exit_code)` which calls the C-level `_exit()` with the code. Perl's `exit()` correctly forwards integer exit codes.

**Edge case:** If the child was killed by a signal, `$? >> 8` gives 0 and the signal is in `$? & 127`. In that case, follow Rust's pattern: `exit_code = WIFEXITED ? WEXITSTATUS : 1`. In Perl:

```perl
my $exit_code;
if (WIFEXITED($?)) {
    $exit_code = WEXITSTATUS($?);
} else {
    $exit_code = 1;
}
```

Where `POSIX::WIFEXITED` / `POSIX::WEXITSTATUS` are used, or manually: `($? & 127) == 0 ? ($? >> 8) : 1`.

**Decision:** Avoid pulling in `POSIX` (technically core but heavy). Use the manual bitmask approach.

## 8. Test Strategy

### Framework: `Test::More` (core)

All tests live in `t/` under the `perl/` directory.

### `t/01_build_prompt_spec.t`

```perl
use Test::More tests => 5;
use Call::Coding::Clis qw(build_prompt_spec);

ok my $spec = build_prompt_spec("hello"), 'valid prompt';
is_deeply $spec->argv, ['opencode', 'run', 'hello'], 'argv correct';

eval { build_prompt_spec("") };
like $@, qr/empty/, 'empty prompt dies';

eval { build_prompt_spec("   ") };
like $@, qr/empty/, 'whitespace-only prompt dies';

ok my $trimmed = build_prompt_spec("  foo  ");
is_deeply $trimmed->argv, ['opencode', 'run', 'foo'], 'whitespace trimmed';
```

### `t/02_runner.t`

Test with a mock executor (coderef injection):

```perl
use Test::More tests => 3;
use Call::Coding::Clis qw(build_prompt_spec);
use Call::Coding::Clis::Runner;

my $spec = build_prompt_spec("test");

my $runner = Call::Coding::Clis::Runner->new(
    executor => sub {
        Call::Coding::Clis::CompletedRun->new(
            argv => ['echo', 'hello'],
            exit_code => 0,
            stdout => "hello\n",
            stderr => '',
        );
    },
);

my $result = $runner->run($spec);
is $result->exit_code, 0, 'mock exit code';
is $result->stdout, "hello\n", 'mock stdout';
is $result->stderr, '', 'mock stderr';
```

Also test startup failure with a nonexistent binary:

```perl
my $real_runner = Call::Coding::Clis::Runner->new;
my $bad_spec = Call::Coding::Clis::CommandSpec->new(argv => ['/nonexistent/binary']);
my $result = $real_runner->run($bad_spec);
like $result->stderr, qr/failed to start \/nonexistent\/binary/, 'startup failure format';
is $result->exit_code, 1, 'startup failure exit code';
```

### `t/03_cli.t`

Test argument validation logic without spawning. Extract `main()` to accept `@ARGV` override:

```perl
# Test via return value capture (STDOUT/STDERR trapping)
# Or test build_prompt_spec directly (covered in 01)
```

### `t/04_ccc_binary.t`

Integration test: run `bin/ccc` as a subprocess with `CCC_REAL_OPENCODE` pointing to a stub. This mirrors the cross-language contract tests.

### `CCC_REAL_OPENCODE` in CLI

Set in `bin/ccc` before calling the runner. Allows contract tests to override the opencode binary with a shell script that prints `opencode run <prompt>`.

## 9. Perl-Specific Considerations

### TMTOWTDI (There's More Than One Way To Do It)

For this implementation, we pick one canonical approach and stick to it:
- **OO style:** Blessed hashrefs, not Moose/Moo/Object::Pad. Minimal, core-only.
- **Subprocess:** `IPC::Open3`, not `system()`, `qx//`, `IPC::Run`, or `Capture::Tiny`.
- **String trimming:** regex `s/^\s+//; s/\s+$//;`, not `Text::Trim`.
- **Testing:** `Test::More`, not `Test2` or `Test::Class`.
- **Exporting:** `Exporter` (core), not `Sub::Exporter`.

### Context Sensitivity

Perl functions are context-sensitive (scalar vs list). Our API must behave correctly in both:
- `build_prompt_spec()` returns a single object — always called in scalar context.
- Accessor methods return scalars — always called in scalar context.
- No list-returning functions in the public API.

### CPAN Packaging

`Makefile.PL`:

```perl
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'Call::Coding::Clis',
    VERSION_FROM  => 'lib/Call/Coding/Clis.pm',
    PREREQ_PM     => {
        'IPC::Open3' => 0,
        'Symbol'     => 0,
        'Test::More' => 0,
    },
    EXE_FILES     => ['bin/ccc'],
    ABSTRACT      => 'Library and CLI for invoking coding assistants',
    LICENSE       => 'unlicense',
);
```

The `bin/ccc` script gets a `#!/usr/bin/env perl` shebang and is installed by `make install`.

### Perl Version Target

Target Perl 5.10+ (2007) for `//` (defined-or) operator. This covers essentially every installed Perl. The `given`/`when` feature is intentionally avoided (experimental in 5.18+, removed in 5.38).

### Strict and Warnings

Every `.pm` and `bin/` file starts with:

```perl
use strict;
use warnings;
```

## 10. Parity Gaps

| Feature | Python | Rust | TypeScript | C | **Perl (planned)** |
|---------|--------|------|------------|---|----|
| build_prompt_spec | yes | yes | yes | yes | **yes** |
| Runner.run | yes | yes | yes | yes | **yes** |
| Runner.stream | yes (real) | yes (fake) | yes (real) | no | **fake (delegates to run)** |
| ccc CLI | yes | yes | yes | yes | **yes** |
| Prompt trimming | yes | yes | yes | yes | **yes** |
| Empty prompt rejection | yes | yes | yes | yes | **yes** |
| Stdin support | yes | yes | yes | yes | **yes** |
| CWD support | yes | yes | yes | yes | **yes** |
| Env support | yes | yes | yes | yes | **yes** |
| Startup failure reporting | yes | yes | yes | yes | **yes** |
| Exit code forwarding | yes | yes | yes | yes | **yes** |
| CCC_REAL_OPENCODE | yes | yes | yes | yes | **yes** |

### Known Gaps vs Other Implementations

1. **No real streaming.** The `stream()` method will delegate to `run()` and fire callbacks afterward, matching the Rust implementation's current behavior. True line-by-line streaming in Perl requires `IO::Select` or `IPC::Run` and adds complexity. This can be added later as an enhancement.

2. **No Executor injection for stream().** The Runner constructor accepts an `executor` coderef for `run()` testability but does not (yet) expose a `stream_executor` hook. This is acceptable since `stream()` delegates to `run()`.

3. **`$@` error message formatting.** Perl's `$@` from `IPC::Open3` exec failure includes the full OS error string. We need to strip and normalize to match the cross-language `"failed to start <argv[0]>: <error>"` format. Testing against the contract test suite will validate this.

4. **No Makefile/CPAN integration tests.** The cross-language contract tests (`tests/test_ccc_contract.py`) will need a Perl invocation added. The simplest approach: `perl perl/bin/ccc "<prompt>"` with `PERL5LIB=perl/lib`.

## Implementation Order

1. `lib/Call/Coding/Clis/CommandSpec.pm`
2. `lib/Call/Coding/Clis/CompletedRun.pm`
3. `lib/Call/Coding/Clis/Runner.pm` (with `_default_run` using `IPC::Open3`)
4. `lib/Call/Coding/Clis.pm` (facade, exports `build_prompt_spec`)
5. `t/01_build_prompt_spec.t`
6. `t/02_runner.t`
7. `bin/ccc`
8. `t/04_ccc_binary.t`
9. `Makefile.PL`
10. Add Perl to cross-language contract tests in `tests/test_ccc_contract.py`
11. Update `IMPLEMENTATION_REFERENCE.md` and `CCC_BEHAVIOR_CONTRACT.md`

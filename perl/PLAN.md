# Perl Implementation Plan

## 1. Directory Structure

```
perl/
├── Makefile.PL
├── MANIFEST
├── lib/
│   └── Call/
│       ├── Coding/
│       │   └── Clis.pm              # facade: exports build_prompt_spec
│       │   └── Clis/
│       │       ├── CommandSpec.pm
│       │       ├── CompletedRun.pm
│       │       └── Runner.pm
│       └── Coding.pm                # empty, satisfies Call::Coding namespace
├── bin/
│   └── ccc
└── t/
    ├── 01_build_prompt_spec.t
    ├── 02_runner.t
    └── 03_ccc_binary.t
```

Namespace: `Call::Coding::Clis`. `Makefile.PL` declares the distribution, dependencies, and installs `bin/ccc`.

### Dependencies (all core)

| Module       | Purpose                          |
|--------------|----------------------------------|
| `IPC::Open3` | subprocess execution with pipe I/O |
| `Symbol`     | `gensym` for stderr pipe handle  |
| `Exporter`   | re-export `build_prompt_spec`    |
| `Test::More` | testing                          |
| `FindBin`    | locate lib/ from bin/ccc         |

No non-core CPAN deps. `IPC::Run` is a future optional upgrade for real streaming.

### MANIFEST

```
bin/ccc
lib/Call/Coding.pm
lib/Call/Coding/Clis.pm
lib/Call/Coding/Clis/CommandSpec.pm
lib/Call/Coding/Clis/CompletedRun.pm
lib/Call/Coding/Clis/Runner.pm
Makefile.PL
MANIFEST
t/01_build_prompt_spec.t
t/02_runner.t
t/03_ccc_binary.t
```

## 2. Build & Run

```sh
# Development (from repo root):
perl -Iperl/lib perl/bin/ccc "Fix the failing tests"

# Build and run tests:
cd perl && perl Makefile.PL && make && make test

# Install system-wide:
make install
```

No build step required for development — `FindBin` + `use lib` resolves paths at runtime.

## 3. Library API

### `Call::Coding::Clis::CommandSpec`

```perl
package Call::Coding::Clis::CommandSpec;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub argv       { $_[0]->{argv} }
sub stdin_text { $_[0]->{stdin_text} }
sub cwd        { $_[0]->{cwd} }
sub env        { $_[0]->{env} // {} }
1;
```

Plain blessed hashref, no Moose/Moo.

### `Call::Coding::Clis::CompletedRun`

```perl
package Call::Coding::Clis::CompletedRun;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless \%args, $class;
}

sub argv      { $_[0]->{argv} }
sub exit_code { $_[0]->{exit_code} }
sub stdout    { $_[0]->{stdout} }
sub stderr    { $_[0]->{stderr} }
1;
```

### `Call::Coding::Clis::Runner`

```perl
package Call::Coding::Clis::Runner;
use strict;
use warnings;
use IPC::Open3;
use Symbol 'gensym';
use Call::Coding::Clis::CommandSpec;
use Call::Coding::Clis::CompletedRun;

sub new {
    my ($class, %opts) = @_;
    my $self = bless {}, $class;
    $self->{executor} = $opts{executor} // \&_default_run;
    return $self;
}

sub run {
    my ($self, $spec) = @_;
    return $self->{executor}->($spec);
}

sub stream {
    my ($self, $spec, $on_event) = @_;
    my $result = $self->run($spec);
    $on_event->('stdout', $result->stdout) if defined $result->stdout && length $result->stdout;
    $on_event->('stderr', $result->stderr) if defined $result->stderr && length $result->stderr;
    return $result;
}

sub _default_run {
    my ($spec) = @_;
    my @argv   = @{$spec->argv};
    my $argv0  = $argv[0];

    local %ENV = (%ENV, %{$spec->env});

    my ($child_pid, $stdin_w, $stdout_r, $stderr_r);
    $stderr_r = gensym;

    eval {
        if (defined $spec->cwd) {
            chdir $spec->cwd or die "chdir to $spec->cwd: $!\n";
        }

        $child_pid = open3($stdin_w, $stdout_r, $stderr_r, @argv);

        if (defined $spec->stdin_text && length $spec->stdin_text) {
            print $stdin_w $spec->stdin_text;
        }
        close $stdin_w;

        my $stdout = do { local $/; <$stdout_r> };
        my $stderr = do { local $/; <$stderr_r> };
        close $stdout_r;
        close $stderr_r;
        waitpid($child_pid, 0);

        my $exit_code = ($? & 127) == 0 ? ($? >> 8) : 1;

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
        (my $err = $@) =~ s/\s+$//;
        return Call::Coding::Clis::CompletedRun->new(
            argv      => \@argv,
            exit_code => 1,
            stdout    => '',
            stderr    => "failed to start $argv0: $err\n",
        );
    }
}
1;
```

**Critical fixes vs draft:**

1. **stdin write before close** — the original draft closed `$stdin_w` before writing. Fixed: write first, then close.
2. **`cwd` support** — `chdir` before `open3` inside the eval block. If `chdir` fails, the die is caught and formatted as a startup error.
3. **Signal-killed child** — exit code uses `($? & 127) == 0 ? ($? >> 8) : 1` instead of bare `$? >> 8`, matching Rust behavior.
4. **`$@` normalization** — trailing whitespace stripped before constructing the error string.
5. **Close read handles** — `close $stdout_r; close $stderr_r` after reading to reap pipe buffers. Neglecting this can lose the child's exit status on some platforms.

**Deadlock caveat:** `IPC::Open3` with separate stdout/stderr pipes can deadlock if the child produces >pipe-buffer-size output on one stream while the parent is blocked reading the other. This is acceptable for our use case (coding CLI output is typically small at the `run()` level). If real streaming is needed later, `IO::Select` or `IPC::Run` would be required.

### `Call::Coding::Clis::build_prompt_spec`

```perl
package Call::Coding::Clis;
use strict;
use warnings;
use Exporter 'import';
use Call::Coding::Clis::CommandSpec;

our @EXPORT_OK = qw(build_prompt_spec);

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
1;
```

### `Call::Coding` (namespace placeholder)

```perl
package Call::Coding;
use strict;
use warnings;
1;
```

Required so `use Call::Coding::Clis` resolves correctly through the `Call::Coding` namespace.

## 4. `bin/ccc` CLI

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use Call::Coding::Clis qw(build_prompt_spec);
use Call::Coding::Clis::Runner;

if (@ARGV != 1) {
    print STDERR 'usage: ccc "<Prompt>"', "\n";
    exit 1;
}

my $spec = eval { build_prompt_spec($ARGV[0]) };
if ($@) {
    print STDERR $@;
    exit 1;
}

if ($ENV{CCC_REAL_OPENCODE}) {
    $spec->{argv}[0] = $ENV{CCC_REAL_OPENCODE};
}

my $runner = Call::Coding::Clis::Runner->new;
my $result = $runner->run($spec);

if (defined $result->stdout && length $result->stdout) {
    print $result->stdout;
}
if (defined $result->stderr && length $result->stderr) {
    print STDERR $result->stderr;
}
exit($result->exit_code);
```

**Key details:**

- `FindBin` + `lib` allows running from source tree without `make install`.
- `CCC_REAL_OPENCODE` overrides argv[0] before execution, matching all other implementations.
- Stdout/stderr printed with `print` (no extra newline) — the subprocess output already contains its own line endings. Uses `if defined ... && length` guard to avoid warnings on undef.

## 5. Prompt Trimming & Empty Rejection

`build_prompt_spec` trims via `s/^\s+//; s/\s+$//;`, dies with `"prompt must not be empty\n"` on empty/whitespace-only input. The CLI catches via `eval`/`if ($@)`, prints `$@` to stderr, exits 1.

Matches Python's `ValueError`, Rust's `Err`, TypeScript's `throw`.

## 6. Error Format: `argv[0]` Only

Contract: `"failed to start <argv[0]>: <error>"`.

```perl
(my $err = $@) =~ s/\s+$//;
stderr => "failed to start $argv0: $err\n",
```

`$@` from `IPC::Open3` exec failure contains the OS error (e.g., `"No such file or directory"`). We strip trailing whitespace and append our own `\n`.

## 7. Exit Code Forwarding

- Normal exit: `$? >> 8`
- Killed by signal: exit code `1` (not the signal number)
- Expression: `($? & 127) == 0 ? ($? >> 8) : 1`
- Avoids pulling in `POSIX` module.

## 8. Test Strategy

### `t/01_build_prompt_spec.t`

```perl
use strict;
use warnings;
use Test::More tests => 6;
use lib 'lib';
use Call::Coding::Clis qw(build_prompt_spec);

ok my $spec = build_prompt_spec("hello"), 'valid prompt';
is_deeply $spec->argv, ['opencode', 'run', 'hello'], 'argv correct';

eval { build_prompt_spec("") };
like $@, qr/empty/, 'empty prompt dies';

eval { build_prompt_spec("   ") };
like $@, qr/empty/, 'whitespace-only prompt dies';

ok my $trimmed = build_prompt_spec("  foo  ");
is_deeply $trimmed->argv, ['opencode', 'run', 'foo'], 'whitespace trimmed';

eval { build_prompt_spec(undef) };
like $@, qr/empty/, 'undef prompt dies';
```

Note: test count is 6 (the draft said 5 but had 6 assertions).

### `t/02_runner.t`

```perl
use strict;
use warnings;
use Test::More tests => 5;
use lib 'lib';
use Call::Coding::Clis qw(build_prompt_spec);
use Call::Coding::Clis::Runner;
use Call::Coding::Clis::CommandSpec;
use Call::Coding::Clis::CompletedRun;

my $spec = build_prompt_spec("test");

my $runner = Call::Coding::Clis::Runner->new(
    executor => sub {
        return Call::Coding::Clis::CompletedRun->new(
            argv      => ['echo', 'hello'],
            exit_code => 0,
            stdout    => "hello\n",
            stderr    => '',
        );
    },
);

my $result = $runner->run($spec);
is $result->exit_code, 0, 'mock exit code';
is $result->stdout, "hello\n", 'mock stdout';
is $result->stderr, '', 'mock stderr';

my $real_runner = Call::Coding::Clis::Runner->new;
my $bad_spec = Call::Coding::Clis::CommandSpec->new(argv => ['/nonexistent_binary_xyz']);
my $bad_result = $real_runner->run($bad_spec);
like $bad_result->stderr, qr/^failed to start \/nonexistent_binary_xyz:/, 'startup failure format';
is $bad_result->exit_code, 1, 'startup failure exit code';
```

### `t/03_ccc_binary.t`

Integration test using `CCC_REAL_OPENCODE` with a shell stub:

```perl
use strict;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp qw(tempfile);
use IPC::Open3;
use Symbol 'gensym';

my ($fh, $stub_path) = tempfile(UNLINK => 1, SUFFIX => '.sh');
print $fh "#!/bin/sh\n";
print $fh "if [ \"\$1\" != \"run\" ]; then exit 9; fi\n";
print $fh "shift\n";
print $fh "printf 'opencode run %s\\\\n' \"\$1\"\n";
close $fh;
chmod 0755, $stub_path;

sub run_ccc {
    my ($prompt) = @_;
    my $ccc = 'bin/ccc';
    my @cmd = ($^X, '-Ilib', $ccc, $prompt);
    local $ENV{CCC_REAL_OPENCODE} = $stub_path;
    my ($stdout, $stderr);
    my $pid = open3(my $in, my $out, gensym, @cmd);
    close $in;
    $stdout = do { local $/; <$out> };
    waitpid($pid, 0);
    return ($stdout // '', '', $? >> 8);
}

my ($out, $err, $rc) = run_ccc("Fix the failing tests");
is $rc, 0, 'happy path exit code';
is $out, "opencode run Fix the failing tests\n", 'happy path stdout';

($out, $err, $rc) = run_ccc("");
isnt $rc, 0, 'empty prompt rejected';

done_testing;
```

Run from `perl/` directory: `prove -v t/`.

## 9. CPAN Packaging

### `Makefile.PL`

```perl
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME          => 'Call::Coding::Clis',
    VERSION_FROM  => 'lib/Call/Coding/Clis.pm',
    PREREQ_PM     => {},
    EXE_FILES     => ['bin/ccc'],
    ABSTRACT      => 'Library and CLI for invoking coding assistants',
    LICENSE       => 'unlicense',
    MIN_PERL_VERSION => '5.010',
);
```

All dependencies are core modules — `PREREQ_PM` is empty. `IPC::Open3`, `Symbol`, `Exporter`, `FindBin`, and `Test::More` ship with every Perl 5.10+.

### Perl Version Target

5.10+ (2007) for the `//` defined-or operator. Avoids `given`/`when` (experimental in 5.18+, removed in 5.38).

## 10. CI Integration

Perl needs no special toolchain. Add to CI alongside the other languages:

```yaml
# GitHub Actions example
- name: Perl tests
  run: |
    cd perl
    perl Makefile.PL
    make
    make test
  env:
    PERL5LIB: ${{ github.workspace }}/perl/lib
```

For cross-language contract tests, Perl is invoked directly (no build step needed):

```perl
subprocess.run(
    ["perl", "perl/bin/ccc", PROMPT],
    cwd=ROOT,
    env={**env, "PERL5LIB": str(ROOT / "perl" / "lib")},
    ...
)
```

## 11. Cross-Language Test Registration

Add Perl to each test method in `tests/test_ccc_contract.py`. Inside the existing `with tempfile.TemporaryDirectory()` block, after the C block:

```python
self.assert_equal_output(
    subprocess.run(
        ["perl", "perl/bin/ccc", PROMPT],
        cwd=ROOT,
        env={**env, "PERL5LIB": str(ROOT / "perl" / "lib")},
        capture_output=True,
        text=True,
        check=False,
    )
)
```

Repeat the same pattern (with appropriate assertion helpers) for:
- `test_cross_language_ccc_rejects_empty_prompt` — use `assert_rejects_empty`
- `test_cross_language_ccc_requires_one_prompt_argument` — use `assert_rejects_missing_prompt`
- `test_cross_language_ccc_rejects_whitespace_only_prompt` — use `assert_rejects_empty`

No build step is needed — `PERL5LIB=perl/lib` and `perl/bin/ccc` run directly from the source tree.

## 12. Parity Matrix

| Feature | Python | Rust | TypeScript | C | **Perl** |
|---------|--------|------|------------|---|----------|
| build_prompt_spec | yes | yes | yes | yes | yes |
| Runner.run | yes | yes | yes | yes | yes |
| Runner.stream | real | fake | real | no | fake |
| ccc CLI | yes | yes | yes | yes | yes |
| Prompt trimming | yes | yes | yes | yes | yes |
| Empty prompt rejection | yes | yes | yes | yes | yes |
| Stdin support | yes | yes | yes | yes | yes |
| CWD support | yes | yes | yes | yes | yes |
| Env support | yes | yes | yes | yes | yes |
| Startup failure format | yes | yes | yes | yes | yes |
| Exit code forwarding | yes | yes | yes | yes | yes |
| Signal-killed child | yes | yes | yes | yes | yes |
| CCC_REAL_OPENCODE | yes | yes | yes | yes | yes |

### Known Gaps

1. **No real streaming** — `stream()` delegates to `run()` and fires callbacks afterward. Acceptable; matches Rust's current behavior. Real streaming requires `IO::Select` or `IPC::Run`.

2. **`IPC::Open3` deadlock risk** — separate stdout/stderr pipes can deadlock with large output. Acceptable for CLI use case. Noted for future `IPC::Run` upgrade path.

## Implementation Order

1. `lib/Call/Coding.pm` (namespace placeholder)
2. `lib/Call/Coding/Clis/CommandSpec.pm`
3. `lib/Call/Coding/Clis/CompletedRun.pm`
4. `lib/Call/Coding/Clis/Runner.pm` (with fixed `_default_run`)
5. `lib/Call/Coding/Clis.pm` (facade, exports `build_prompt_spec`)
6. `t/01_build_prompt_spec.t`
7. `t/02_runner.t`
8. `bin/ccc`
9. `t/03_ccc_binary.t`
10. `Makefile.PL`
11. `MANIFEST`
12. Add Perl to `tests/test_ccc_contract.py` (all 4 test methods)
13. Update `IMPLEMENTATION_REFERENCE.md` and `CCC_BEHAVIOR_CONTRACT.md`

use strict;
use warnings;
use Test::More;
use lib 'lib';
use File::Temp qw(tempfile);
use Call::Coding::Clis::Config qw(load_config);
use Call::Coding::Clis::Parser qw(parse_args resolve_command);

{
    my $p   = parse_args("hello");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['opencode', 'run', 'hello'], 'default runner: opencode run';
    is_deeply $cmd->{env}, {}, 'default runner: no env';
}

{
    my $p   = parse_args("claude", "hello");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['claude', 'hello'], 'claude runner: argv';
}

{
    my $p   = parse_args("c", "hello");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['codex', 'hello'], 'c runner: argv';
}

{
    my $p   = parse_args("cx", "hello");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['codex', 'hello'], 'cx runner: argv';
}

{
    my $p   = parse_args("claude", "+3", "think deep");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['claude', '--thinking', 'high', 'think deep'], 'claude thinking flags';
}

{
    my $p   = parse_args("claude", ":gpt-4o", "test");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['claude', '--model', 'gpt-4o', 'test'], 'claude model flag';
}

{
    my $p   = parse_args(":anthropic:claude-3.5", "test");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{env}, { CCC_PROVIDER => 'anthropic' }, 'provider env var';
}

{
    my $p = parse_args();
    eval { resolve_command($p) };
    like $@, qr/prompt must not be empty/, 'empty prompt dies';
}

{
    my $p = parse_args("   ");
    eval { resolve_command($p) };
    like $@, qr/prompt must not be empty/, 'whitespace prompt dies';
}

{
    my $p   = parse_args("cc", "+1", "hello");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['claude', '--thinking', 'low', 'hello'], 'cc abbreviation resolves to claude';
}

{
    my $p   = parse_args("k", "+0", "hello");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['kimi', '--no-think', 'hello'], 'k abbreviation resolves to kimi';
}

{
    my $p   = parse_args("codex", ":gpt-4o", "test");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['codex', '--model', 'gpt-4o', 'test'], 'codex model flag';
}

{
    my $p   = parse_args("rc", "hello");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['roocode', 'hello'], 'rc runner: argv';
}

{
    my $p   = parse_args("crush", "test");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['crush', 'test'], 'crush no model flag';
}

{
    my $p   = parse_args(":openai:gpt-4o", "test");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{env}, { CCC_PROVIDER => 'openai' }, 'provider from provider:model';
}

{
    my $config = {
        default_runner => 'claude',
    };
    my $p   = parse_args("hello");
    my $cmd = resolve_command($p, $config);
    is_deeply $cmd->{argv}, ['claude', 'hello'], 'config default_runner';
}

{
    my $config = {
        aliases => {
            fast => { runner => 'claude', thinking => 1, provider => '', model => '', agent => '' },
        },
    };
    my $p   = parse_args('@fast', "hello");
    my $cmd = resolve_command($p, $config);
    is_deeply $cmd->{argv}, ['claude', '--thinking', 'low', 'hello'], 'alias overrides runner+thinking';
}

{
    my $p   = parse_args('@reviewer', "hello");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['opencode', 'run', '--agent', 'reviewer', 'hello'], 'name fallback uses agent';
    is_deeply $cmd->{warnings}, [], 'supported agent emits no warning';
}

{
    my $config = {
        aliases => {
            reviewer => { agent => 'specialist', runner => '', thinking => undef, provider => '', model => '' },
        },
    };
    my $p   = parse_args('@reviewer', "hello");
    my $cmd = resolve_command($p, $config);
    is_deeply $cmd->{argv}, ['opencode', 'run', '--agent', 'specialist', 'hello'], 'preset agent wins over name fallback';
}

{
    my $p   = parse_args('codex', '@reviewer', "hello");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['codex', 'hello'], 'unsupported agent is ignored';
    is_deeply $cmd->{warnings}, ['warning: runner "codex" does not support agents; ignoring @reviewer'], 'unsupported agent warns';
}

{
    my $p   = parse_args('rc', '@reviewer', "hello");
    my $cmd = resolve_command($p);
    is_deeply $cmd->{argv}, ['roocode', 'hello'], 'roocode unsupported agent is ignored';
    is_deeply $cmd->{warnings}, ['warning: runner "rc" does not support agents; ignoring @reviewer'], 'roocode unsupported agent warns';
}

{
    my $config = {
        default_thinking => 2,
    };
    my $p   = parse_args("claude", "hello");
    my $cmd = resolve_command($p, $config);
    is_deeply $cmd->{argv}, ['claude', '--thinking', 'medium', 'hello'], 'config default_thinking';
}

{
    my ($fh, $path) = tempfile(SUFFIX => '.toml');
    print $fh <<'TOML';
[aliases.work]
runner = "cc"
thinking = 3
model = "claude-4"
agent = "reviewer"
TOML
    close $fh;

    my $config = load_config($path);
    is $config->{aliases}{work}{runner}, 'cc', 'config alias runner';
    is $config->{aliases}{work}{thinking}, 3, 'config alias thinking';
    is $config->{aliases}{work}{model}, 'claude-4', 'config alias model';
    is $config->{aliases}{work}{agent}, 'reviewer', 'config alias agent';
}

done_testing;

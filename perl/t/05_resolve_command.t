use strict;
use warnings;
use Test::More;
use lib 'lib';
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
            fast => { runner => 'claude', thinking => 1, provider => '', model => '' },
        },
    };
    my $p   = parse_args('@fast', "hello");
    my $cmd = resolve_command($p, $config);
    is_deeply $cmd->{argv}, ['claude', '--thinking', 'low', 'hello'], 'alias overrides runner+thinking';
}

{
    my $config = {
        default_thinking => 2,
    };
    my $p   = parse_args("claude", "hello");
    my $cmd = resolve_command($p, $config);
    is_deeply $cmd->{argv}, ['claude', '--thinking', 'medium', 'hello'], 'config default_thinking';
}

done_testing;

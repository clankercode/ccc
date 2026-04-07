use strict;
use warnings;
use Test::More;
use lib 'lib';
use Call::Coding::Clis::Parser qw(parse_args resolve_command runner_registry);

my $reg = runner_registry();
ok $reg->{opencode}, 'registry has opencode';
ok $reg->{oc},       'registry has oc abbreviation';
ok $reg->{claude},   'registry has claude';
ok $reg->{cc},       'registry has cc abbreviation';
ok $reg->{c},        'registry has c abbreviation';
ok $reg->{kimi},     'registry has kimi';
ok $reg->{k},        'registry has k abbreviation';
ok $reg->{codex},    'registry has codex';
ok $reg->{rc},       'registry has rc abbreviation';
ok $reg->{crush},    'registry has crush';
ok $reg->{cr},       'registry has cr abbreviation';

{
    my $p = parse_args("hello world");
    is $p->{prompt},  'hello world', 'prompt-only: prompt';
    is $p->{runner},  undef,         'prompt-only: no runner';
    is $p->{thinking}, undef,        'prompt-only: no thinking';
    is $p->{provider}, undef,        'prompt-only: no provider';
    is $p->{model},    undef,        'prompt-only: no model';
    is $p->{alias},    undef,        'prompt-only: no alias';
}

{
    my $p = parse_args("claude", "do stuff");
    is $p->{runner}, 'claude',   'runner selector: runner';
    is $p->{prompt}, 'do stuff', 'runner selector: prompt';
}

{
    my $p = parse_args("+3", "think hard");
    is $p->{thinking}, 3,          'thinking: level';
    is $p->{prompt},   'think hard', 'thinking: prompt';
}

{
    my $p = parse_args(":anthropic:claude-3.5", "test");
    is $p->{provider}, 'anthropic',  'provider:model: provider';
    is $p->{model},    'claude-3.5', 'provider:model: model';
    is $p->{prompt},   'test',       'provider:model: prompt';
}

{
    my $p = parse_args(":gpt-4o", "test");
    is $p->{model},  'gpt-4o', 'model only: model';
    is $p->{prompt}, 'test',   'model only: prompt';
}

{
    my $p = parse_args('@work', "test");
    is $p->{alias},  'work', 'alias: alias';
    is $p->{prompt}, 'test', 'alias: prompt';
}

{
    my $p = parse_args("cc", "+2", ":openai:gpt-4o", '@fast', "do it");
    is $p->{runner},   'cc',     'full combo: runner';
    is $p->{thinking}, 2,        'full combo: thinking';
    is $p->{provider}, 'openai', 'full combo: provider';
    is $p->{model},    'gpt-4o', 'full combo: model';
    is $p->{alias},    'fast',   'full combo: alias';
    is $p->{prompt},   'do it',  'full combo: prompt';
}

{
    my $p = parse_args("OC", "test");
    is $p->{runner}, 'oc', 'runner selector is lowercased';
}

done_testing;

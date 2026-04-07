use strict;
use warnings;
use Test::More tests => 7;
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

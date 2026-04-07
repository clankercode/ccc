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

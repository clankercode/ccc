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
print $fh "printf 'opencode run %s\\n' \"\$1\"\n";
close $fh;
chmod 0755, $stub_path;

sub run_ccc {
    my ($prompt) = @_;
    my $ccc = 'bin/ccc';
    my @cmd = ($^X, '-Ilib', $ccc, $prompt);
    local $ENV{CCC_REAL_OPENCODE} = $stub_path;
    local $ENV{CCC_CONFIG};
    delete $ENV{CCC_CONFIG};
    local $ENV{XDG_CONFIG_HOME} = '/tmp/ccc-test-no-config-$$';
    my ($stdout, $stderr);
    $stderr = gensym;
    my $pid = open3(my $in, my $out, $stderr, @cmd);
    close $in;
    $stdout = do { local $/; <$out> };
    my $err_data = do { local $/; <$stderr> };
    waitpid($pid, 0);
    return ($stdout // '', $err_data // '', $? >> 8);
}

my ($out, $err, $rc) = run_ccc("Fix the failing tests");
is $rc, 0, 'happy path exit code';
is $out, "opencode run Fix the failing tests\n", 'happy path stdout';

($out, $err, $rc) = run_ccc("");
isnt $rc, 0, 'empty prompt rejected';

done_testing;

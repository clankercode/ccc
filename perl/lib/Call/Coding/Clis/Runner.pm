package Call::Coding::Clis::Runner;
use strict;
use warnings;
use Cwd;
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
    my $orig_cwd;

    my $result = eval {
        if (defined $spec->cwd) {
            $orig_cwd = Cwd::getcwd();
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

        if (defined $orig_cwd) {
            chdir $orig_cwd;
        }

        my $exit_code = ($? & 127) == 0 ? ($? >> 8) : 1;

        $stdout //= '';
        $stderr //= '';

        Call::Coding::Clis::CompletedRun->new(
            argv      => \@argv,
            exit_code => $exit_code,
            stdout    => $stdout,
            stderr    => $stderr,
        );
    };
    if ($@) {
        if (defined $orig_cwd) {
            chdir $orig_cwd;
        }
        (my $err = $@) =~ s/\s+$//;
        return Call::Coding::Clis::CompletedRun->new(
            argv      => \@argv,
            exit_code => 1,
            stdout    => '',
            stderr    => "failed to start $argv0: $err\n",
        );
    }
    return $result;
}
1;

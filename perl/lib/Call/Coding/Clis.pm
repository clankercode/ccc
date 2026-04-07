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

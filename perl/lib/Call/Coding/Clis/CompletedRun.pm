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

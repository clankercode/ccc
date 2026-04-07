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

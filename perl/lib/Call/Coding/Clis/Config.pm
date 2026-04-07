package Call::Coding::Clis::Config;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(load_config);

sub load_config {
    my ($path) = @_;
    open my $fh, '<', $path or die "cannot open $path: $!\n";

    my $config = {
        default_runner   => 'oc',
        default_provider => '',
        default_model    => '',
        default_thinking => undef,
        aliases          => {},
        abbreviations    => {},
    };

    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next if $line eq '' || $line =~ /^#/;

        if ($line =~ /^(\w+)\s*=\s*(.*)$/) {
            my ($key, $val) = ($1, $2);
            $val =~ s/^\s+//;
            $val =~ s/\s+$//;

            if ($key eq 'default_runner') {
                $config->{default_runner} = $val;
            }
            elsif ($key eq 'default_provider') {
                $config->{default_provider} = $val;
            }
            elsif ($key eq 'default_model') {
                $config->{default_model} = $val;
            }
            elsif ($key eq 'default_thinking') {
                $config->{default_thinking} = ($val =~ /^[0-4]$/ ? $val + 0 : undef);
            }
            elsif ($key eq 'alias') {
                if ($val =~ /^(\w+)\s+runner=(\S+)(?:\s+thinking=([0-4]))?(?:\s+provider=(\S+))?(?:\s+model=(\S+))?$/) {
                    $config->{aliases}{$1} = {
                        runner   => $2,
                        thinking => (defined $3 ? $3 + 0 : undef),
                        provider => ($4 // ''),
                        model    => ($5 // ''),
                    };
                }
            }
            elsif ($key eq 'abbrev') {
                if ($val =~ /^(\S+)\s*=\s*(\S+)$/) {
                    $config->{abbreviations}{$1} = $2;
                }
            }
        }
    }

    close $fh;
    return $config;
}

1;

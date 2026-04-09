package Call::Coding::Clis::Config;
use strict;
use warnings;
use Exporter 'import';
use File::Spec;

our @EXPORT_OK = qw(load_config find_config_path);

sub find_config_path {
    my $ccc_config = $ENV{CCC_CONFIG};
    return $ccc_config if defined $ccc_config && -f $ccc_config && -s $ccc_config;

    my $xdg = $ENV{XDG_CONFIG_HOME};
    if (defined $xdg && length $xdg) {
        my $p = File::Spec->catfile($xdg, 'ccc', 'config.toml');
        return $p if -f $p;
    }

    my $home = $ENV{HOME};
    if (defined $home && length $home) {
        my $p = File::Spec->catfile($home, '.config', 'ccc', 'config.toml');
        return $p if -f $p;
    }

    return undef;
}

sub load_config {
    my ($path) = @_;

    if (!defined $path) {
        $path = find_config_path();
        return _empty_config() unless defined $path;
    }

    return _empty_config() unless -f $path;

    open my $fh, '<', $path or return _empty_config();
    my $content = do { local $/; <$fh> };
    close $fh;

    return _parse_legacy($content) if $path !~ /\.toml$/i;
    return _parse_toml($content);
}

sub _empty_config {
    return {
        default_runner   => 'oc',
        default_provider => '',
        default_model    => '',
        default_thinking => undef,
        aliases          => {},
        abbreviations    => {},
    };
}

sub _parse_toml {
    my ($content) = @_;

    my $config = _empty_config();
    my $in_defaults = 0;
    my $in_abbreviations = 0;
    my $in_aliases = 0;
    my $current_alias;

    for my $line (split /\n/, $content) {
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next if $line eq '' || $line =~ /^#/;

        if ($line eq '[defaults]') {
            $in_defaults = 1;
            $in_abbreviations = 0;
            $in_aliases = 0;
            next;
        }
        elsif ($line eq '[abbreviations]') {
            $in_defaults = 0;
            $in_abbreviations = 1;
            $in_aliases = 0;
            next;
        }
        elsif ($line =~ /^\[aliases\.([^\]]+)\]$/) {
            $in_defaults = 0;
            $in_abbreviations = 0;
            $in_aliases = 1;
            $current_alias = $1;
            $config->{aliases}{$current_alias} //= {
                runner   => '',
                thinking => undef,
                provider => '',
                model    => '',
                agent    => '',
            };
            next;
        }
        elsif ($line =~ /^\[/) {
            $in_defaults = 0;
            $in_abbreviations = 0;
            $in_aliases = 0;
            next;
        }

        if ($line =~ /^(\S+)\s*=\s*(.*)$/) {
            my ($key, $val) = ($1, $2);
            $val =~ s/^\s+//;
            $val =~ s/\s+$//;
            $val =~ s/^"(.*)"$/$1/;

            if ($in_defaults) {
                if ($key eq 'runner') {
                    $config->{default_runner} = $val;
                }
                elsif ($key eq 'provider') {
                    $config->{default_provider} = $val;
                }
                elsif ($key eq 'model') {
                    $config->{default_model} = $val;
                }
                elsif ($key eq 'thinking') {
                    $config->{default_thinking} = ($val =~ /^[0-4]$/ ? $val + 0 : undef);
                }
            }
            elsif ($in_abbreviations) {
                $config->{abbreviations}{$key} = $val;
            }
            elsif ($in_aliases && defined $current_alias) {
                if ($key eq 'runner') {
                    $config->{aliases}{$current_alias}{runner} = $val;
                }
                elsif ($key eq 'thinking') {
                    $config->{aliases}{$current_alias}{thinking} = ($val =~ /^[0-4]$/ ? $val + 0 : undef);
                }
                elsif ($key eq 'provider') {
                    $config->{aliases}{$current_alias}{provider} = $val;
                }
                elsif ($key eq 'model') {
                    $config->{aliases}{$current_alias}{model} = $val;
                }
                elsif ($key eq 'agent') {
                    $config->{aliases}{$current_alias}{agent} = $val;
                }
            }
        }
    }

    return $config;
}

sub _parse_legacy {
    my ($content) = @_;

    my $config = _empty_config();

    for my $line (split /\n/, $content) {
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
                if ($val =~ /^(\w+)\s+runner=(\S+)(?:\s+thinking=([0-4]))?(?:\s+provider=(\S+))?(?:\s+model=(\S+))?(?:\s+agent=(\S+))?$/) {
                    $config->{aliases}{$1} = {
                        runner   => $2,
                        thinking => (defined $3 ? $3 + 0 : undef),
                        provider => ($4 // ''),
                        model    => ($5 // ''),
                        agent    => ($6 // ''),
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

    return $config;
}

1;

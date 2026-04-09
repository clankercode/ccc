package Call::Coding::Clis::Help;
use strict;
use warnings;
use Exporter 'import';
use File::Which qw(which);
use Call::Coding::Clis::Parser qw(runner_registry);

our @EXPORT_OK = qw(HELP_TEXT runner_checklist print_help print_usage);

my @CANONICAL_RUNNERS = (
    ['opencode', 'oc'],
    ['claude',   'cc'],
    ['kimi',     'k'],
    ['codex',    'rc'],
    ['crush',    'cr'],
);

our $HELP_TEXT = <<'END_HELP';
ccc — call coding CLIs

Usage:
  ccc [runner] [+thinking] [:provider:model] [@alias] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)
  +thinking     Set thinking level: +0 (off) through +4 (max)
  :provider:model  Override provider and model
  @alias        Use a named preset from config

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc k +4 "Debug the parser"
  ccc codex "Write a unit test"

Config:
  ~/.config/ccc/config.toml  — default runner, aliases, abbreviations
END_HELP

sub _get_version {
    my ($binary) = @_;
    my $version = '';
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm(3);
        my $pid = open(my $fh, '-|', $binary, '--version');
        die "cannot run $binary: $!\n" unless $pid;
        local $/;
        my $output = <$fh>;
        close $fh;
        alarm(0);
        if (defined $output && $? == 0 && $output =~ /\S/) {
            ($version) = $output =~ /^([^\n]+)/;
        }
    };
    alarm(0);
    return $version // '';
}

sub runner_checklist {
    my $registry = runner_registry();
    my @lines = ("Runners:");
    for my $entry (@CANONICAL_RUNNERS) {
        my ($name, $alias) = @$entry;
        my $info   = $registry->{$name};
        my $binary = $info ? $info->{binary} : $name;
        my $found  = which($binary);
        if ($found) {
            my $version = _get_version($binary);
            my $tag = length($version) ? $version : "found";
            push @lines, sprintf("  [+] %-10s (%s)  %s", $name, $binary, $tag);
        }
        else {
            push @lines, sprintf("  [-] %-10s (%s)  not found", $name, $binary);
        }
    }
    return join("\n", @lines);
}

sub print_help {
    print $HELP_TEXT, "\n", runner_checklist(), "\n";
}

sub print_usage {
    print STDERR 'usage: ccc [runner] [+thinking] [:provider:model] [@alias] "<Prompt>"', "\n";
    print STDERR runner_checklist(), "\n";
}

1;

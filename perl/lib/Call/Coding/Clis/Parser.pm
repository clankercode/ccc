package Call::Coding::Clis::Parser;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(parse_args resolve_command runner_registry);

my %RUNNER_REGISTRY;

sub _register_defaults {
    return if %RUNNER_REGISTRY;

    %RUNNER_REGISTRY = (
        opencode => {
            binary         => 'opencode',
            extra_args     => ['run'],
            thinking_flags => {},
            provider_flag  => '',
            model_flag     => '',
            agent_flag     => '--agent',
        },
        claude => {
            binary         => 'claude',
            extra_args     => [],
            thinking_flags => {
                0 => ['--thinking', 'disabled'],
                1 => ['--thinking', 'enabled', '--effort', 'low'],
                2 => ['--thinking', 'enabled', '--effort', 'medium'],
                3 => ['--thinking', 'enabled', '--effort', 'high'],
                4 => ['--thinking', 'enabled', '--effort', 'max'],
            },
            provider_flag => '',
            model_flag    => '--model',
            agent_flag    => '--agent',
        },
        kimi => {
            binary         => 'kimi',
            extra_args     => [],
            thinking_flags => {
                0 => ['--no-thinking'],
                1 => ['--thinking'],
                2 => ['--thinking'],
                3 => ['--thinking'],
                4 => ['--thinking'],
            },
            provider_flag => '',
            model_flag    => '--model',
            agent_flag    => '--agent',
        },
        codex => {
            binary         => 'codex',
            extra_args     => ['exec'],
            thinking_flags => {},
            provider_flag  => '',
            model_flag     => '--model',
            agent_flag     => '',
        },
        roocode => {
            binary         => 'roocode',
            extra_args     => [],
            thinking_flags => {},
            provider_flag  => '',
            model_flag     => '',
            agent_flag     => '',
        },
        crush => {
            binary         => 'crush',
            extra_args     => [],
            thinking_flags => {},
            provider_flag  => '',
            model_flag     => '',
            agent_flag     => '',
        },
    );

    $RUNNER_REGISTRY{oc} = $RUNNER_REGISTRY{opencode};
    $RUNNER_REGISTRY{cc} = $RUNNER_REGISTRY{claude};
    $RUNNER_REGISTRY{c}  = $RUNNER_REGISTRY{codex};
    $RUNNER_REGISTRY{cx} = $RUNNER_REGISTRY{codex};
    $RUNNER_REGISTRY{k}  = $RUNNER_REGISTRY{kimi};
    $RUNNER_REGISTRY{rc} = $RUNNER_REGISTRY{roocode};
    $RUNNER_REGISTRY{cr} = $RUNNER_REGISTRY{crush};
}

_register_defaults();

my $RUNNER_SELECTOR_RE = qr/^(?:oc|cc|c|cx|k|rc|cr|codex|claude|opencode|kimi|roocode|crush|pi)$/i;
my $THINKING_RE        = qr/^\+([0-4])$/;
my $PROVIDER_MODEL_RE  = qr/^:([a-zA-Z0-9_-]+):([a-zA-Z0-9._-]+)$/;
my $MODEL_RE           = qr/^:([a-zA-Z0-9._-]+)$/;
my $ALIAS_RE           = qr/^@([a-zA-Z0-9_-]+)$/;

sub parse_args {
    my @argv = @_;

    my $parsed = {
        runner   => undef,
        thinking => undef,
        provider => undef,
        model    => undef,
        alias    => undef,
        prompt   => '',
    };

    my @positional;

    for my $token (@argv) {
        if ($token =~ $RUNNER_SELECTOR_RE && !defined $parsed->{runner} && !@positional) {
            $parsed->{runner} = lc $token;
        }
        elsif ($token =~ $THINKING_RE && !@positional) {
            $parsed->{thinking} = $1 + 0;
        }
        elsif ($token =~ $PROVIDER_MODEL_RE && !@positional) {
            $parsed->{provider} = $1;
            $parsed->{model}    = $2;
        }
        elsif ($token =~ $MODEL_RE && !@positional) {
            $parsed->{model} = $1;
        }
        elsif ($token =~ $ALIAS_RE && !defined $parsed->{alias} && !@positional) {
            $parsed->{alias} = $1;
        }
        else {
            push @positional, $token;
        }
    }

    $parsed->{prompt} = join(' ', @positional);
    return $parsed;
}

sub resolve_command {
    my ($parsed, $config) = @_;
    $config //= {};
    my @warnings;

    my $default_runner = $config->{default_runner} // 'oc';
    my $runner_name    = $parsed->{runner} // $default_runner;

    my $abbreviations = $config->{abbreviations} // {};
    if (defined $parsed->{runner} && $abbreviations->{$runner_name}) {
        $runner_name = $abbreviations->{$runner_name};
    }

    my $info = $RUNNER_REGISTRY{$runner_name}
        // $RUNNER_REGISTRY{$default_runner}
        // $RUNNER_REGISTRY{opencode};

    my $alias_def;
    if (defined $parsed->{alias} && ($config->{aliases} || {})->{$parsed->{alias}}) {
        $alias_def = $config->{aliases}{$parsed->{alias}};
    }
    my $requested_agent = defined $parsed->{alias} && !$alias_def ? $parsed->{alias} : undef;

    my $effective_runner_name = $runner_name;
    if ($alias_def && $alias_def->{runner} && !defined $parsed->{runner}) {
        $effective_runner_name = $alias_def->{runner};
        if ($abbreviations->{$effective_runner_name}) {
            $effective_runner_name = $abbreviations->{$effective_runner_name};
        }
        $info = $RUNNER_REGISTRY{$effective_runner_name} // $info;
    }

    my @argv = ($info->{binary}, @{$info->{extra_args}});

    my $effective_thinking = $parsed->{thinking};
    if (!defined $effective_thinking && $alias_def && defined $alias_def->{thinking}) {
        $effective_thinking = $alias_def->{thinking};
    }
    if (!defined $effective_thinking) {
        $effective_thinking = $config->{default_thinking};
    }
    if (defined $effective_thinking && ($info->{thinking_flags} || {})->{$effective_thinking}) {
        push @argv, @{$info->{thinking_flags}{$effective_thinking}};
    }

    my $effective_provider = $parsed->{provider};
    if (!defined $effective_provider && $alias_def && $alias_def->{provider}) {
        $effective_provider = $alias_def->{provider};
    }
    if (!defined $effective_provider) {
        $effective_provider = $config->{default_provider};
    }

    my $effective_model = $parsed->{model};
    if (!defined $effective_model && $alias_def && $alias_def->{model}) {
        $effective_model = $alias_def->{model};
    }
    if (!defined $effective_model) {
        $effective_model = $config->{default_model};
    }

    if ($effective_model && $info->{model_flag}) {
        push @argv, $info->{model_flag}, $effective_model;
    }

    my $effective_agent = $requested_agent;
    if (!defined $effective_agent && $alias_def && $alias_def->{agent}) {
        $effective_agent = $alias_def->{agent};
    }
    if (defined $effective_agent && length $effective_agent) {
        if ($info->{agent_flag}) {
            push @argv, $info->{agent_flag}, $effective_agent;
        }
        else {
            push @warnings, sprintf(
                'warning: runner "%s" does not support agents; ignoring @%s',
                $effective_runner_name, $effective_agent
            );
        }
    }

    my %env_overrides;
    if ($effective_provider) {
        $env_overrides{CCC_PROVIDER} = $effective_provider;
    }

    my $prompt = $parsed->{prompt};
    $prompt =~ s/^\s+//;
    $prompt =~ s/\s+$//;
    die "prompt must not be empty\n" unless length $prompt;

    push @argv, $prompt;

    return { argv => \@argv, env => \%env_overrides, warnings => \@warnings };
}

sub runner_registry {
    return \%RUNNER_REGISTRY;
}

1;

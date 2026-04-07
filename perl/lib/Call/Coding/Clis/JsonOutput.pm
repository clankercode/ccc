package Call::Coding::Clis::JsonOutput;
use strict;
use warnings;
use Exporter 'import';
use JSON::PP;

our @EXPORT_OK = qw(
    parse_opencode_json
    parse_claude_code_json
    parse_kimi_json
    parse_json_output
    render_parsed
);

my @KIMI_PASSTHROUGH = qw(
    TurnBegin StepBegin StepInterrupted TurnEnd StatusUpdate
    HookTriggered HookResolved ApprovalRequest SubagentEvent ToolCallRequest
);
my %KIMI_PASSTHROUGH = map { $_ => 1 } @KIMI_PASSTHROUGH;

sub _tool_call {
    my ($id, $name, $arguments) = @_;
    return { id => $id, name => $name, arguments => $arguments };
}

sub _tool_result {
    my ($tool_call_id, $content, $is_error) = @_;
    return { tool_call_id => $tool_call_id, content => $content, is_error => $is_error // 0 };
}

sub _event {
    my (%args) = @_;
    return {
        event_type  => $args{event_type},
        text        => $args{text} // '',
        thinking    => $args{thinking} // '',
        tool_call   => $args{tool_call},
        tool_result => $args{tool_result},
        raw         => $args{raw} // {},
    };
}

sub _result {
    my (%args) = @_;
    return {
        schema_name => $args{schema_name},
        events      => $args{events} // [],
        final_text  => $args{final_text} // '',
        session_id  => $args{session_id} // '',
        error       => $args{error} // '',
        usage       => $args{usage} // {},
        cost_usd    => $args{cost_usd} // 0.0,
        duration_ms => $args{duration_ms} // 0,
        raw_lines   => $args{raw_lines} // [],
    };
}

sub parse_opencode_json {
    my ($raw_stdout) = @_;
    my $result = _result(schema_name => 'opencode');
    my $json = JSON::PP->new->utf8;

    for my $line (split /\n/, ($raw_stdout // '')) {
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next unless length $line;

        my $obj;
        eval { $obj = $json->decode($line) };
        next if $@;

        push @{$result->{raw_lines}}, $obj;

        if (exists $obj->{response}) {
            my $text = $obj->{response};
            $result->{final_text} = $text;
            push @{$result->{events}}, _event(event_type => 'text', text => $text, raw => $obj);
        }
        elsif (exists $obj->{error}) {
            $result->{error} = $obj->{error};
            push @{$result->{events}}, _event(event_type => 'error', text => $obj->{error}, raw => $obj);
        }
    }
    return $result;
}

sub parse_claude_code_json {
    my ($raw_stdout) = @_;
    my $result = _result(schema_name => 'claude-code');
    my $json = JSON::PP->new->utf8;

    for my $line (split /\n/, ($raw_stdout // '')) {
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next unless length $line;

        my $obj;
        eval { $obj = $json->decode($line) };
        next if $@;

        push @{$result->{raw_lines}}, $obj;
        my $msg_type = $obj->{type} // '';

        if ($msg_type eq 'system') {
            my $sub = $obj->{subtype} // '';
            if ($sub eq 'init') {
                $result->{session_id} = $obj->{session_id} // '';
            }
            elsif ($sub eq 'api_retry') {
                push @{$result->{events}}, _event(event_type => 'system_retry', raw => $obj);
            }
        }
        elsif ($msg_type eq 'assistant') {
            my $message = $obj->{message} // {};
            my $content = $message->{content} // [];
            my @texts;
            for my $block (@$content) {
                if (ref($block) eq 'HASH' && ($block->{type} // '') eq 'text') {
                    push @texts, ($block->{text} // '');
                }
            }
            if (@texts) {
                my $text = join("\n", @texts);
                $result->{final_text} = $text;
                push @{$result->{events}}, _event(event_type => 'assistant', text => $text, raw => $obj);
            }
            my $usage = $message->{usage};
            $result->{usage} = $usage if $usage;
        }
        elsif ($msg_type eq 'stream_event') {
            my $event = $obj->{event} // {};
            my $et = $event->{type} // '';
            if ($et eq 'content_block_delta') {
                my $delta = $event->{delta} // {};
                my $dt = $delta->{type} // '';
                if ($dt eq 'text_delta') {
                    push @{$result->{events}}, _event(event_type => 'text_delta', text => ($delta->{text} // ''), raw => $obj);
                }
                elsif ($dt eq 'thinking_delta') {
                    push @{$result->{events}}, _event(event_type => 'thinking_delta', thinking => ($delta->{thinking} // ''), raw => $obj);
                }
                elsif ($dt eq 'input_json_delta') {
                    push @{$result->{events}}, _event(event_type => 'tool_input_delta', text => ($delta->{partial_json} // ''), raw => $obj);
                }
            }
            elsif ($et eq 'content_block_start') {
                my $cb = $event->{content_block} // {};
                my $cbt = $cb->{type} // '';
                if ($cbt eq 'thinking') {
                    push @{$result->{events}}, _event(event_type => 'thinking_start', raw => $obj);
                }
                elsif ($cbt eq 'tool_use') {
                    my $tc = _tool_call($cb->{id} // '', $cb->{name} // '', '');
                    push @{$result->{events}}, _event(event_type => 'tool_use_start', tool_call => $tc, raw => $obj);
                }
            }
        }
        elsif ($msg_type eq 'tool_use') {
            my $tc = _tool_call('', $obj->{tool_name} // '', $json->encode($obj->{tool_input} // {}));
            push @{$result->{events}}, _event(event_type => 'tool_use', tool_call => $tc, raw => $obj);
        }
        elsif ($msg_type eq 'tool_result') {
            my $tr = _tool_result($obj->{tool_use_id} // '', $obj->{content} // '', $obj->{is_error} ? 1 : 0);
            push @{$result->{events}}, _event(event_type => 'tool_result', tool_result => $tr, raw => $obj);
        }
        elsif ($msg_type eq 'result') {
            my $sub = $obj->{subtype} // '';
            if ($sub eq 'success') {
                $result->{final_text} = exists $obj->{result} ? $obj->{result} : $result->{final_text};
                $result->{cost_usd} = exists $obj->{cost_usd} ? $obj->{cost_usd} : $result->{cost_usd};
                $result->{duration_ms} = exists $obj->{duration_ms} ? $obj->{duration_ms} : $result->{duration_ms};
                $result->{usage} = exists $obj->{usage} ? $obj->{usage} : $result->{usage};
                push @{$result->{events}}, _event(event_type => 'result', text => $result->{final_text}, raw => $obj);
            }
            elsif ($sub eq 'error') {
                $result->{error} = $obj->{error} // '';
                push @{$result->{events}}, _event(event_type => 'error', text => $result->{error}, raw => $obj);
            }
        }
    }
    return $result;
}

sub parse_kimi_json {
    my ($raw_stdout) = @_;
    my $result = _result(schema_name => 'kimi');
    my $json = JSON::PP->new->utf8;

    for my $line (split /\n/, ($raw_stdout // '')) {
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        next unless length $line;

        my $obj;
        eval { $obj = $json->decode($line) };
        next if $@;

        push @{$result->{raw_lines}}, $obj;

        my $wire_type = $obj->{type} // '';
        if ($KIMI_PASSTHROUGH{$wire_type}) {
            push @{$result->{events}}, _event(event_type => lc($wire_type), raw => $obj);
            next;
        }

        my $role = $obj->{role} // '';

        if ($role eq 'assistant') {
            my $content = $obj->{content};
            my $tool_calls = $obj->{tool_calls};

            if (!ref($content)) {
                $result->{final_text} = $content;
                push @{$result->{events}}, _event(event_type => 'assistant', text => $content, raw => $obj);
            }
            elsif (ref($content) eq 'ARRAY') {
                my @texts;
                for my $part (@$content) {
                    next unless ref($part) eq 'HASH';
                    my $pt = $part->{type} // '';
                    if ($pt eq 'text') {
                        push @texts, ($part->{text} // '');
                    }
                    elsif ($pt eq 'think') {
                        push @{$result->{events}}, _event(event_type => 'thinking', thinking => ($part->{think} // ''), raw => $obj);
                    }
                }
                if (@texts) {
                    my $text = join("\n", @texts);
                    $result->{final_text} = $text;
                    push @{$result->{events}}, _event(event_type => 'assistant', text => $text, raw => $obj);
                }
            }

            if ($tool_calls) {
                for my $tc_data (@$tool_calls) {
                    my $fn = $tc_data->{function} // {};
                    my $tc = _tool_call($tc_data->{id} // '', $fn->{name} // '', $fn->{arguments} // '');
                    push @{$result->{events}}, _event(event_type => 'tool_call', tool_call => $tc, raw => $obj);
                }
            }
        }
        elsif ($role eq 'tool') {
            my $content = $obj->{content} // [];
            my @texts;
            for my $part (@$content) {
                if (ref($part) eq 'HASH' && ($part->{type} // '') eq 'text') {
                    my $text = $part->{text} // '';
                    push @texts, $text unless $text =~ /^<system>/;
                }
            }
            my $tr = _tool_result($obj->{tool_call_id} // '', join("\n", @texts), 0);
            push @{$result->{events}}, _event(event_type => 'tool_result', tool_result => $tr, raw => $obj);
        }
    }
    return $result;
}

my %PARSERS = (
    'opencode'    => \&parse_opencode_json,
    'claude-code' => \&parse_claude_code_json,
    'kimi'        => \&parse_kimi_json,
);

sub parse_json_output {
    my ($raw_stdout, $schema) = @_;
    my $parser = $PARSERS{$schema};
    unless ($parser) {
        return _result(schema_name => $schema, error => "unknown schema: $schema");
    }
    return $parser->($raw_stdout);
}

sub render_parsed {
    my ($output) = @_;
    my @parts;
    for my $event (@{$output->{events}}) {
        my $et = $event->{event_type};
        if ($et eq 'text' || $et eq 'assistant' || $et eq 'result') {
            push @parts, $event->{text} if defined $event->{text} && length $event->{text};
        }
        elsif ($et eq 'thinking_delta' || $et eq 'thinking') {
            push @parts, "[thinking] $event->{thinking}" if defined $event->{thinking} && length $event->{thinking};
        }
        elsif ($et eq 'tool_use') {
            push @parts, "[tool] $event->{tool_call}{name}" if $event->{tool_call};
        }
        elsif ($et eq 'tool_result') {
            push @parts, "[tool_result] $event->{tool_result}{content}" if $event->{tool_result};
        }
        elsif ($et eq 'error') {
            push @parts, "[error] $event->{text}" if defined $event->{text} && length $event->{text};
        }
    }
    return @parts ? join("\n", @parts) : ($output->{final_text} // '');
}

1;

<?php

namespace Call\Coding\Clis;

class CompletedRun
{
    public readonly array $argv;
    public readonly int $exit_code;
    public readonly string $stdout;
    public readonly string $stderr;

    public function __construct(
        array $argv,
        int $exit_code,
        string $stdout = '',
        string $stderr = ''
    ) {
        $this->argv = $argv;
        $this->exit_code = $exit_code;
        $this->stdout = $stdout;
        $this->stderr = $stderr;
    }
}

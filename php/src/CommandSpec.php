<?php

namespace Call\Coding\Clis;

class CommandSpec
{
    public array $argv;
    public readonly ?string $stdin_text;
    public readonly ?string $cwd;
    public readonly array $env;

    public function __construct(
        array $argv,
        ?string $stdin_text = null,
        ?string $cwd = null,
        array $env = []
    ) {
        $this->argv = $argv;
        $this->stdin_text = $stdin_text;
        $this->cwd = $cwd;
        $this->env = $env;
    }
}

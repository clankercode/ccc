<?php

namespace Call\Coding\Clis;

function build_prompt_spec(?string $prompt): CommandSpec
{
    $prompt = $prompt ?? '';
    $trimmed = trim($prompt);
    if ($trimmed === '') {
        throw new \InvalidArgumentException("prompt must not be empty\n");
    }
    return new CommandSpec(['opencode', 'run', $trimmed]);
}

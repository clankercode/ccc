<?php

namespace Call\Coding\Clis;

class Help
{
    private const CANONICAL_RUNNERS = [
        ['name' => 'opencode', 'alias' => 'oc'],
        ['name' => 'claude', 'alias' => 'cc'],
        ['name' => 'kimi', 'alias' => 'k'],
        ['name' => 'codex', 'alias' => 'rc'],
        ['name' => 'crush', 'alias' => 'cr'],
    ];

    private const HELP_TEXT = <<<'TXT'
ccc — call coding CLIs

Usage:
  ccc [runner] [+thinking] [:provider:model] [@name] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)
  +thinking     Set thinking level: +0 (off) through +4 (max)
  :provider:model  Override provider and model
  @name         Use a named preset from config; if no preset exists, treat it as an agent

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc k +4 "Debug the parser"
  ccc @reviewer "Audit the API boundary"
  ccc codex "Write a unit test"

Config:
  ~/.config/ccc/config.toml  — default runner, presets, abbreviations

TXT;

    private static function getVersion(string $binary): string
    {
        $descriptors = [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ];

        $process = proc_open("{$binary} --version", $descriptors, $pipes);
        if (!is_resource($process)) {
            return '';
        }

        $stdout = stream_get_contents($pipes[1]);
        fclose($pipes[0]);
        fclose($pipes[1]);
        fclose($pipes[2]);

        $exitCode = proc_close($process);
        $stdout = trim($stdout);

        if ($exitCode === 0 && $stdout !== '') {
            $firstLine = explode("\n", $stdout, 2)[0];
            return $firstLine;
        }

        return '';
    }

    public static function runnerChecklist(): string
    {
        $registry = Parser::getRegistry();
        $lines = ['Runners:'];

        foreach (self::CANONICAL_RUNNERS as $entry) {
            $name = $entry['name'];
            $binary = ($registry[$name] ?? null)?->binary ?? $name;

            $found = false;
            $which = shell_exec('which ' . escapeshellarg($binary) . ' 2>/dev/null');
            if ($which !== null && trim($which) !== '') {
                $found = true;
            }

            if ($found) {
                $version = self::getVersion($binary);
                $tag = $version !== '' ? $version : 'found';
                $lines[] = sprintf("  [+] %-10s (%s)  %s", $name, $binary, $tag);
            } else {
                $lines[] = sprintf("  [-] %-10s (%s)  not found", $name, $binary);
            }
        }

        return implode("\n", $lines);
    }

    public static function printHelp(): void
    {
        fwrite(STDOUT, self::HELP_TEXT . "\n" . self::runnerChecklist() . "\n");
    }

    public static function printUsage(): void
    {
        fwrite(STDERR, 'usage: ccc [runner] [+thinking] [:provider:model] [@name] "<Prompt>"' . "\n");
        fwrite(STDERR, self::runnerChecklist() . "\n");
    }
}

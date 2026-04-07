<?php

namespace Call\Coding\Clis;

class Config
{
    public static function loadConfig(?string $path = null): CccConfig
    {
        $config = new CccConfig();

        if ($path === null) {
            $homeDir = getenv('HOME') ?: getenv('USERPROFILE') ?: '/tmp';
            $path = $homeDir . '/.config/ccc/config';
        }

        if (!file_exists($path)) {
            return $config;
        }

        $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        if ($lines === false) {
            return $config;
        }

        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '#')) {
                continue;
            }

            $eqPos = strpos($line, '=');
            if ($eqPos === false) {
                continue;
            }

            $key = trim(substr($line, 0, $eqPos));
            $value = trim(substr($line, $eqPos + 1));

            if ($value === '') {
                continue;
            }

            switch ($key) {
                case 'default_runner':
                    $config->defaultRunner = $value;
                    break;
                case 'default_provider':
                    $config->defaultProvider = $value;
                    break;
                case 'default_model':
                    $config->defaultModel = $value;
                    break;
                case 'default_thinking':
                    $config->defaultThinking = (int) $value;
                    break;
                case 'alias':
                    self::parseAlias($config, $value);
                    break;
                case 'abbrev':
                    $config->abbreviations[$value] = $value;
                    break;
            }
        }

        return $config;
    }

    private static function parseAlias(CccConfig $config, string $value): void
    {
        $parts = preg_split('/\s+/', $value);
        if (count($parts) < 2) {
            return;
        }

        $name = array_shift($parts);
        $def = new AliasDef();

        foreach ($parts as $part) {
            if (preg_match('/^runner=(.+)$/', $part, $m)) {
                $def->runner = $m[1];
            } elseif (preg_match('/^thinking=([0-4])$/', $part, $m)) {
                $def->thinking = (int) $m[1];
            } elseif (preg_match('/^provider=(.+)$/', $part, $m)) {
                $def->provider = $m[1];
            } elseif (preg_match('/^model=(.+)$/', $part, $m)) {
                $def->model = $m[1];
            }
        }

        $config->aliases[$name] = $def;
    }
}

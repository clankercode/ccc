<?php

namespace Call\Coding\Clis;

class Config
{
    public static function loadConfig(?string $path = null): CccConfig
    {
        foreach (self::configPaths($path) as $candidate) {
            $config = self::loadFromPath($candidate);
            if ($config !== null) {
                return $config;
            }
        }

        return new CccConfig();
    }

    private static function configPaths(?string $path): array
    {
        if ($path !== null) {
            return [$path];
        }

        $paths = [];
        $explicit = getenv('CCC_CONFIG');
        if (is_string($explicit) && $explicit !== '') {
            $paths[] = $explicit;
        }

        $xdgDir = getenv('XDG_CONFIG_HOME');
        if (is_string($xdgDir) && $xdgDir !== '') {
            $paths[] = $xdgDir . '/ccc/config.toml';
            $paths[] = $xdgDir . '/ccc/config';
        }

        $homeDir = getenv('HOME') ?: getenv('USERPROFILE') ?: '/tmp';
        $paths[] = $homeDir . '/.config/ccc/config.toml';
        $paths[] = $homeDir . '/.config/ccc/config';

        return $paths;
    }

    private static function loadFromPath(string $path): ?CccConfig
    {
        if (!file_exists($path)) {
            return null;
        }

        $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        if ($lines === false) {
            return null;
        }

        $config = new CccConfig();
        $section = null;
        $aliasName = null;

        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '#')) {
                continue;
            }

            if ($line[0] === '[' && str_ends_with($line, ']')) {
                $section = substr($line, 1, -1);
                $aliasName = str_starts_with($section, 'aliases.')
                    ? substr($section, strlen('aliases.'))
                    : null;
                continue;
            }

            $eqPos = strpos($line, '=');
            if ($eqPos === false) {
                continue;
            }

            $key = trim(substr($line, 0, $eqPos));
            $value = self::stripQuotes(trim(substr($line, $eqPos + 1)));

            if ($value === '') {
                continue;
            }

            if ($section === 'defaults') {
                switch ($key) {
                    case 'runner':
                        $config->defaultRunner = $value;
                        break;
                    case 'provider':
                        $config->defaultProvider = $value;
                        break;
                    case 'model':
                        $config->defaultModel = $value;
                        break;
                    case 'thinking':
                        $config->defaultThinking = (int) $value;
                        break;
                }
                continue;
            }

            if ($section === 'abbreviations') {
                $config->abbreviations[$key] = $value;
                continue;
            }

            if ($aliasName !== null && $aliasName !== '') {
                $alias = $config->aliases[$aliasName] ?? new AliasDef();
                switch ($key) {
                    case 'runner':
                        $alias->runner = $value;
                        break;
                    case 'thinking':
                        $alias->thinking = (int) $value;
                        break;
                    case 'provider':
                        $alias->provider = $value;
                        break;
                    case 'model':
                        $alias->model = $value;
                        break;
                }
                $config->aliases[$aliasName] = $alias;
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
                    self::parseAbbrev($config, $value);
                    break;
            }
        }

        return $config;
    }

    private static function stripQuotes(string $value): string
    {
        if (strlen($value) >= 2 && $value[0] === '"' && $value[strlen($value) - 1] === '"') {
            return substr($value, 1, -1);
        }
        return $value;
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

    private static function parseAbbrev(CccConfig $config, string $value): void
    {
        if (preg_match('/^(\S+)\s*=\s*(\S+)$/', $value, $m)) {
            $config->abbreviations[$m[1]] = $m[2];
        }
    }
}

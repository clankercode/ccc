<?php

namespace Call\Coding\Clis;

class RunnerInfo
{
    public string $binary;
    public array $extraArgs;
    public array $thinkingFlags;
    public string $providerFlag;
    public string $modelFlag;
    public string $agentFlag;

    public function __construct(
        string $binary,
        array $extraArgs = [],
        array $thinkingFlags = [],
        string $providerFlag = '',
        string $modelFlag = '',
        string $agentFlag = ''
    ) {
        $this->binary = $binary;
        $this->extraArgs = $extraArgs;
        $this->thinkingFlags = $thinkingFlags;
        $this->providerFlag = $providerFlag;
        $this->modelFlag = $modelFlag;
        $this->agentFlag = $agentFlag;
    }
}

class ParsedArgs
{
    public ?string $runner = null;
    public ?int $thinking = null;
    public ?string $provider = null;
    public ?string $model = null;
    public ?string $alias = null;
    public string $prompt = '';
}

class AliasDef
{
    public ?string $runner = null;
    public ?int $thinking = null;
    public ?string $provider = null;
    public ?string $model = null;
    public ?string $agent = null;
}

class CccConfig
{
    public string $defaultRunner = 'oc';
    public string $defaultProvider = '';
    public string $defaultModel = '';
    public ?int $defaultThinking = null;
    public array $aliases = [];
    public array $abbreviations = [];
}

class Parser
{
    private static ?array $runnerRegistry = null;

    private const RUNNER_SELECTOR_RE = '/^(?:oc|cc|c|cx|k|rc|cr|codex|claude|opencode|kimi|roocode|crush|pi)$/i';
    private const THINKING_RE = '/^\+([0-4])$/';
    private const PROVIDER_MODEL_RE = '/^:([a-zA-Z0-9_-]+):([a-zA-Z0-9._-]+)$/';
    private const MODEL_RE = '/^:([a-zA-Z0-9._-]+)$/';
    private const ALIAS_RE = '/^@([a-zA-Z0-9_-]+)$/';

    public static function getRegistry(): array
    {
        if (self::$runnerRegistry !== null) {
            return self::$runnerRegistry;
        }

        self::$runnerRegistry = [];

        self::$runnerRegistry['opencode'] = new RunnerInfo(
            'opencode',
            ['run'],
            [],
            '',
            '',
            '--agent'
        );

        self::$runnerRegistry['claude'] = new RunnerInfo(
            'claude',
            [],
            [
                0 => ['--thinking', 'disabled'],
                1 => ['--thinking', 'enabled', '--effort', 'low'],
                2 => ['--thinking', 'enabled', '--effort', 'medium'],
                3 => ['--thinking', 'enabled', '--effort', 'high'],
                4 => ['--thinking', 'enabled', '--effort', 'max'],
            ],
            '',
            '--model',
            '--agent'
        );

        self::$runnerRegistry['kimi'] = new RunnerInfo(
            'kimi',
            [],
            [
                0 => ['--no-thinking'],
                1 => ['--thinking'],
                2 => ['--thinking'],
                3 => ['--thinking'],
                4 => ['--thinking'],
            ],
            '',
            '--model',
            '--agent'
        );

        self::$runnerRegistry['codex'] = new RunnerInfo(
            'codex',
            [],
            [],
            '',
            '--model'
        );

        self::$runnerRegistry['roocode'] = new RunnerInfo(
            'roocode',
            [],
            [],
            '',
            '--model'
        );

        self::$runnerRegistry['crush'] = new RunnerInfo(
            'crush',
            [],
            [],
            '',
            ''
        );

        self::$runnerRegistry['oc'] = self::$runnerRegistry['opencode'];
        self::$runnerRegistry['cc'] = self::$runnerRegistry['claude'];
        self::$runnerRegistry['c'] = self::$runnerRegistry['codex'];
        self::$runnerRegistry['cx'] = self::$runnerRegistry['codex'];
        self::$runnerRegistry['k'] = self::$runnerRegistry['kimi'];
        self::$runnerRegistry['rc'] = self::$runnerRegistry['roocode'];
        self::$runnerRegistry['cr'] = self::$runnerRegistry['crush'];

        return self::$runnerRegistry;
    }

    public static function parseArgs(array $argv): ParsedArgs
    {
        $parsed = new ParsedArgs();
        $positional = [];

        foreach ($argv as $token) {
            if (preg_match(self::RUNNER_SELECTOR_RE, $token)
                && $parsed->runner === null
                && empty($positional)
            ) {
                $parsed->runner = strtolower($token);
            } elseif (preg_match(self::THINKING_RE, $token, $m) && empty($positional)) {
                $parsed->thinking = (int) $m[1];
            } elseif (preg_match(self::PROVIDER_MODEL_RE, $token, $m) && empty($positional)) {
                $parsed->provider = $m[1];
                $parsed->model = $m[2];
            } elseif (preg_match(self::MODEL_RE, $token, $m) && empty($positional)) {
                $parsed->model = $m[1];
            } elseif (preg_match(self::ALIAS_RE, $token, $m)
                && $parsed->alias === null
                && empty($positional)
            ) {
                $parsed->alias = $m[1];
            } else {
                $positional[] = $token;
            }
        }

        $parsed->prompt = implode(' ', $positional);
        return $parsed;
    }

    private static function resolveRunnerName(?string $name, CccConfig $config): string
    {
        if ($name === null) {
            return $config->defaultRunner;
        }
        return $config->abbreviations[$name] ?? $name;
    }

    public static function resolveCommand(ParsedArgs $parsed, ?CccConfig $config = null, ?array &$warnings = null): array
    {
        if ($config === null) {
            $config = new CccConfig();
        }
        $warnings = [];

        $registry = self::getRegistry();
        $runnerName = self::resolveRunnerName($parsed->runner, $config);

        $info = $registry[$runnerName]
            ?? $registry[$config->defaultRunner]
            ?? $registry['opencode'];

        $aliasDef = null;
        if ($parsed->alias !== null && isset($config->aliases[$parsed->alias])) {
            $aliasDef = $config->aliases[$parsed->alias];
        }
        $requestedAgent = ($parsed->alias !== null && $aliasDef === null) ? $parsed->alias : null;

        $effectiveRunnerName = $runnerName;
        if ($aliasDef !== null && $aliasDef->runner !== null && $parsed->runner === null) {
            $effectiveRunnerName = self::resolveRunnerName($aliasDef->runner, $config);
            $info = $registry[$effectiveRunnerName] ?? $info;
        }

        $cmdArgv = array_merge([$info->binary], $info->extraArgs);

        $effectiveThinking = $parsed->thinking;
        if ($effectiveThinking === null && $aliasDef !== null && $aliasDef->thinking !== null) {
            $effectiveThinking = $aliasDef->thinking;
        }
        if ($effectiveThinking === null) {
            $effectiveThinking = $config->defaultThinking;
        }
        if ($effectiveThinking !== null && isset($info->thinkingFlags[$effectiveThinking])) {
            $cmdArgv = array_merge($cmdArgv, $info->thinkingFlags[$effectiveThinking]);
        }

        $effectiveProvider = $parsed->provider;
        if ($effectiveProvider === null && $aliasDef !== null && $aliasDef->provider !== null) {
            $effectiveProvider = $aliasDef->provider;
        }
        if ($effectiveProvider === null) {
            $effectiveProvider = $config->defaultProvider;
        }

        $effectiveModel = $parsed->model;
        if ($effectiveModel === null && $aliasDef !== null && $aliasDef->model !== null) {
            $effectiveModel = $aliasDef->model;
        }
        if ($effectiveModel === null) {
            $effectiveModel = $config->defaultModel;
        }

        if ($effectiveModel !== '' && $effectiveModel !== null && $info->modelFlag !== '') {
            $cmdArgv[] = $info->modelFlag;
            $cmdArgv[] = $effectiveModel;
        }

        $effectiveAgent = $requestedAgent;
        if ($effectiveAgent === null && $aliasDef !== null && $aliasDef->agent !== null && $aliasDef->agent !== '') {
            $effectiveAgent = $aliasDef->agent;
        }
        if ($effectiveAgent !== null && $effectiveAgent !== '') {
            if ($info->agentFlag !== '') {
                $cmdArgv[] = $info->agentFlag;
                $cmdArgv[] = $effectiveAgent;
            } else {
                $warnings[] = sprintf(
                    'warning: runner "%s" does not support agents; ignoring @%s',
                    $info->binary,
                    $effectiveAgent
                );
            }
        }

        $envOverrides = [];
        if ($effectiveProvider !== '' && $effectiveProvider !== null) {
            $envOverrides['CCC_PROVIDER'] = $effectiveProvider;
        }

        $prompt = trim($parsed->prompt);
        if ($prompt === '') {
            throw new \ValueError('prompt must not be empty');
        }

        $cmdArgv[] = $prompt;

        return ['argv' => $cmdArgv, 'env' => $envOverrides, 'warnings' => $warnings];
    }
}

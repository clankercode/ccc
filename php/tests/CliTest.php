#!/usr/bin/env php
<?php

$passed = 0;
$failed = 0;

function assert_test(string $name, bool $condition): void
{
    global $passed, $failed;
    if ($condition) {
        $passed++;
        echo "ok - $name\n";
    } else {
        $failed++;
        echo "not ok - $name\n";
    }
}

function make_dir(string $prefix): string
{
    $dir = sys_get_temp_dir() . '/' . $prefix . uniqid('', true);
    mkdir($dir, 0777, true);
    return $dir;
}

function write_executable(string $path, string $content): void
{
    file_put_contents($path, $content);
    chmod($path, 0755);
}

function run_ccc(array $args, array $env = []): array
{
    $descriptors = [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ];
    $command = array_merge([PHP_BINARY, __DIR__ . '/../bin/ccc'], $args);
    $env = array_merge(getenv(), $env);
    $proc = proc_open($command, $descriptors, $pipes, dirname(__DIR__), $env);
    if (!is_resource($proc)) {
        throw new RuntimeException('failed to start ccc');
    }
    fclose($pipes[0]);
    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    $exitCode = proc_close($proc);
    return [$stdout ?? '', $stderr ?? '', $exitCode];
}

function set_env(string $name, ?string $value): ?string
{
    $old = getenv($name);
    if ($value === null) {
        putenv($name);
    } else {
        putenv($name . '=' . $value);
    }
    return $old === false ? null : $old;
}

function restore_env(string $name, ?string $value): void
{
    if ($value === null) {
        putenv($name);
    } else {
        putenv($name . '=' . $value);
    }
}

$base = make_dir('ccc_php_cli_');
$configBase = make_dir('ccc_php_cli_cfg_');
mkdir($configBase . '/home/.config/ccc', 0777, true);
mkdir($configBase . '/xdg/ccc', 0777, true);
file_put_contents($configBase . '/empty-config.toml', '');

$oldHome = set_env('HOME', $configBase . '/home');
$oldXdg = set_env('XDG_CONFIG_HOME', $configBase . '/xdg');
$oldCcc = set_env('CCC_CONFIG', $configBase . '/empty-config.toml');

try {
    [$stdout, $stderr, $rc] = run_ccc(['--help']);
    assert_test('help exits 0', $rc === 0);
    assert_test('help mentions @name', str_contains($stdout, '[@name]'));
    assert_test('help explains agent fallback', str_contains($stdout, 'if no preset exists, treat it as an agent'));
    assert_test('help mentions codex selectors', str_contains($stdout, 'codex (c/cx)'));
    assert_test('help mentions roocode selector', str_contains($stdout, 'roocode (rc)'));

    $binDir = $base . '/bin';
    mkdir($binDir, 0777, true);
    write_executable(
        $binDir . '/opencode',
        <<<'SH'
#!/bin/sh
if [ "$1" != "run" ]; then
  exit 9
fi
shift
if [ "$1" = "--agent" ]; then
  printf 'opencode run --agent %s %s\n' "$2" "$3"
else
  printf 'opencode run %s\n' "$1"
fi
SH
    );
    write_executable(
        $binDir . '/claude',
        <<<'SH'
#!/bin/sh
printf 'claude %s\n' "$*"
SH
    );
    write_executable(
        $binDir . '/codex',
        <<<'SH'
#!/bin/sh
if [ "$1" != "exec" ]; then
  exit 9
fi
shift
printf 'codex exec %s\n' "$*"
SH
    );
    write_executable(
        $binDir . '/roocode',
        <<<'SH'
#!/bin/sh
printf 'roocode %s\n' "$*"
SH
    );

    $pathEnv = ['PATH' => $binDir . ':' . getenv('PATH')];

    [$stdout, $stderr, $rc] = run_ccc(['c', 'Fix the failing tests'], $pathEnv);
    assert_test('selector c exit code', $rc === 0);
    assert_test('selector c stdout', $stdout === "codex exec Fix the failing tests\n");
    assert_test('selector c stderr empty', $stderr === '');

    [$stdout, $stderr, $rc] = run_ccc(['cx', 'Fix the failing tests'], $pathEnv);
    assert_test('selector cx exit code', $rc === 0);
    assert_test('selector cx stdout', $stdout === "codex exec Fix the failing tests\n");
    assert_test('selector cx stderr empty', $stderr === '');

    [$stdout, $stderr, $rc] = run_ccc(['cc', 'Fix the failing tests'], $pathEnv);
    assert_test('selector cc exit code', $rc === 0);
    assert_test('selector cc stdout', $stdout === "claude Fix the failing tests\n");
    assert_test('selector cc stderr empty', $stderr === '');

    [$stdout, $stderr, $rc] = run_ccc(['rc', 'Fix the failing tests'], $pathEnv);
    assert_test('selector rc exit code', $rc === 0);
    assert_test('selector rc stdout', $stdout === "roocode Fix the failing tests\n");
    assert_test('selector rc stderr empty', $stderr === '');

    [$stdout, $stderr, $rc] = run_ccc(['@reviewer', 'Fix the failing tests'], $pathEnv);
    assert_test('name fallback exit code', $rc === 0);
    assert_test('name fallback stdout', $stdout === "opencode run --agent reviewer Fix the failing tests\n");
    assert_test('name fallback stderr empty', $stderr === '');

    $home = $base . '/home';
    mkdir($home . '/.config/ccc', 0777, true);
    file_put_contents($home . '/.config/ccc/config.toml', "[defaults]\nrunner = \"codex\"\n");
    $legacy = $base . '/legacy-config';
    file_put_contents($legacy, '');

    $testOldHome = set_env('HOME', $home);
    $testOldXdg = set_env('XDG_CONFIG_HOME', $base . '/xdg');
    $testOldCcc = set_env('CCC_CONFIG', $legacy);
    try {
        [$stdout, $stderr, $rc] = run_ccc(
            ['@reviewer', 'Fix the failing tests'],
            ['PATH' => $binDir . ':' . getenv('PATH')]
        );
        assert_test('unsupported agent exit code', $rc === 0);
        assert_test('unsupported agent warning', str_contains($stderr, 'warning: runner "codex" does not support agents; ignoring @reviewer'));
        assert_test('unsupported agent stdout', $stdout === "codex exec Fix the failing tests\n");
    } finally {
        restore_env('CCC_CONFIG', $testOldCcc);
        restore_env('XDG_CONFIG_HOME', $testOldXdg);
        restore_env('HOME', $testOldHome);
    }
} finally {
    restore_env('CCC_CONFIG', $oldCcc);
    restore_env('XDG_CONFIG_HOME', $oldXdg);
    restore_env('HOME', $oldHome);
    echo "\n";
    echo "Results: $passed passed, $failed failed\n";
}

exit($failed > 0 ? 1 : 0);

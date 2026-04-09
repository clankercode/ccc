#!/usr/bin/env php
<?php

require_once __DIR__ . '/../src/Parser.php';
require_once __DIR__ . '/../src/Config.php';

use Call\Coding\Clis\Config;

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

$base = sys_get_temp_dir() . '/ccc_php_config_' . uniqid('', true);
mkdir($base, 0777, true);

try {
    $explicit = $base . '/config.toml';
    file_put_contents(
        $explicit,
        "[defaults]\nrunner = \"cc\"\n\n[aliases.work]\nrunner = \"claude\"\nthinking = 3\nprovider = \"anthropic\"\nmodel = \"claude-4\"\nagent = \"reviewer\"\n"
    );

    $config = Config::loadConfig($explicit);
    assert_test('explicit config default runner', $config->defaultRunner === 'cc');
    assert_test('explicit config alias agent', $config->aliases['work']->agent === 'reviewer');

    $home = $base . '/home';
    $xdg = $base . '/xdg';
    $legacy = $base . '/legacy-config';
    mkdir($home . '/.config/ccc', 0777, true);
    mkdir($xdg, 0777, true);
    file_put_contents($home . '/.config/ccc/config.toml', "[defaults]\nrunner = \"claude\"\n\n[aliases.review]\nagent = \"specialist\"\n");
    file_put_contents($legacy, '');

    $oldHome = set_env('HOME', $home);
    $oldXdg = set_env('XDG_CONFIG_HOME', $xdg);
    $oldCcc = set_env('CCC_CONFIG', $legacy);
    try {
        $config = Config::loadConfig();
        assert_test('empty CCC_CONFIG falls through to home config', $config->defaultRunner === 'claude');
        assert_test('fallback config agent parsed', $config->aliases['review']->agent === 'specialist');
    } finally {
        restore_env('CCC_CONFIG', $oldCcc);
        restore_env('XDG_CONFIG_HOME', $oldXdg);
        restore_env('HOME', $oldHome);
    }
} finally {
    echo "\n";
    echo "Results: $passed passed, $failed failed\n";
}

exit($failed > 0 ? 1 : 0);

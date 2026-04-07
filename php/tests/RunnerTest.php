#!/usr/bin/env php
<?php

require_once __DIR__ . '/../src/CommandSpec.php';
require_once __DIR__ . '/../src/CompletedRun.php';
require_once __DIR__ . '/../src/Runner.php';
require_once __DIR__ . '/../src/build_prompt_spec.php';

use Call\Coding\Clis\CommandSpec;
use Call\Coding\Clis\CompletedRun;
use Call\Coding\Clis\Runner;
use function Call\Coding\Clis\build_prompt_spec;

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

$spec = build_prompt_spec("hello");
assert_test('valid prompt argv', $spec->argv === ['opencode', 'run', 'hello']);

try {
    build_prompt_spec("");
    assert_test('empty prompt throws', false);
} catch (\InvalidArgumentException $e) {
    assert_test('empty prompt throws', str_contains($e->getMessage(), 'empty'));
}

try {
    build_prompt_spec("   ");
    assert_test('whitespace-only prompt throws', false);
} catch (\InvalidArgumentException $e) {
    assert_test('whitespace-only prompt throws', str_contains($e->getMessage(), 'empty'));
}

$trimmed = build_prompt_spec("  foo  ");
assert_test('whitespace trimmed', $trimmed->argv === ['opencode', 'run', 'foo']);

try {
    build_prompt_spec(null);
    assert_test('null prompt throws', false);
} catch (\InvalidArgumentException $e) {
    assert_test('null prompt throws', str_contains($e->getMessage(), 'empty'));
}

$mockRunner = new Runner(function (CommandSpec $spec): CompletedRun {
    return new CompletedRun(['echo', 'hello'], 0, "hello\n", '');
});

$result = $mockRunner->run(build_prompt_spec("test"));
assert_test('mock exit code', $result->exit_code === 0);
assert_test('mock stdout', $result->stdout === "hello\n");
assert_test('mock stderr', $result->stderr === '');

$realRunner = new Runner();
$badSpec = new CommandSpec(['/nonexistent_binary_xyz']);
$badResult = $realRunner->run($badSpec);
assert_test('startup failure format', str_starts_with($badResult->stderr, "failed to start /nonexistent_binary_xyz:"));
assert_test('startup failure exit code', $badResult->exit_code === 1);

$stubScript = <<<'SH'
#!/bin/sh
if [ "$1" != "run" ]; then exit 9; fi
shift
printf 'opencode run %s\n' "$1"
SH;

$tmpFile = tempnam(sys_get_temp_dir(), 'ccc_test_');
file_put_contents($tmpFile, $stubScript);
chmod($tmpFile, 0755);

function run_ccc(string $prompt, string $stubPath): array
{
    $descriptors = [
        0 => ['pipe', 'r'],
        1 => ['pipe', 'w'],
        2 => ['pipe', 'w'],
    ];
    $env = array_merge(getenv(), ['CCC_REAL_OPENCODE' => $stubPath]);
    $proc = proc_open(
        [PHP_BINARY, __DIR__ . '/../bin/ccc', $prompt],
        $descriptors,
        $pipes,
        null,
        $env
    );
    fclose($pipes[0]);
    $stdout = stream_get_contents($pipes[1]);
    $stderr = stream_get_contents($pipes[2]);
    fclose($pipes[1]);
    fclose($pipes[2]);
    $exitCode = proc_close($proc);
    return [$stdout ?? '', $stderr ?? '', $exitCode];
}

list($out, $err, $rc) = run_ccc("Fix the failing tests", $tmpFile);
assert_test('ccc happy path exit code', $rc === 0);
assert_test('ccc happy path stdout', $out === "opencode run Fix the failing tests\n");

list($out, $err, $rc) = run_ccc("", $tmpFile);
assert_test('ccc empty prompt rejected', $rc !== 0);

unlink($tmpFile);

echo "\n";
echo "Results: $passed passed, $failed failed\n";
exit($failed > 0 ? 1 : 0);

#!/usr/bin/env php
<?php

require_once __DIR__ . '/../src/CommandSpec.php';
require_once __DIR__ . '/../src/CompletedRun.php';
require_once __DIR__ . '/../src/Runner.php';
require_once __DIR__ . '/../src/Parser.php';
require_once __DIR__ . '/../src/Config.php';
require_once __DIR__ . '/../src/build_prompt_spec.php';

use Call\Coding\Clis\Parser;
use Call\Coding\Clis\ParsedArgs;
use Call\Coding\Clis\CccConfig;
use Call\Coding\Clis\AliasDef;
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

// --- parseArgs tests ---

$p = Parser::parseArgs(['hello world']);
assert_test('prompt-only: prompt', $p->prompt === 'hello world');
assert_test('prompt-only: runner null', $p->runner === null);
assert_test('prompt-only: thinking null', $p->thinking === null);

$p = Parser::parseArgs(['claude', 'fix this']);
assert_test('runner selector: runner', $p->runner === 'claude');
assert_test('runner selector: prompt', $p->prompt === 'fix this');

$p = Parser::parseArgs(['+3', 'think hard']);
assert_test('thinking: level', $p->thinking === 3);
assert_test('thinking: prompt', $p->prompt === 'think hard');

$p = Parser::parseArgs([':openai:gpt-4o', 'go']);
assert_test('provider:model: provider', $p->provider === 'openai');
assert_test('provider:model: model', $p->model === 'gpt-4o');

$p = Parser::parseArgs([':gpt-4o-mini', 'go']);
assert_test('model only: model', $p->model === 'gpt-4o-mini');
assert_test('model only: provider null', $p->provider === null);

$p = Parser::parseArgs(['@fast', 'do it']);
assert_test('alias: name', $p->alias === 'fast');

$p = Parser::parseArgs(['claude', '+2', ':gpt-4o', 'full combo']);
assert_test('full combo: runner', $p->runner === 'claude');
assert_test('full combo: thinking', $p->thinking === 2);
assert_test('full combo: model', $p->model === 'gpt-4o');
assert_test('full combo: prompt', $p->prompt === 'full combo');

$p = Parser::parseArgs(['CC', 'upper runner']);
assert_test('runner case-insensitive', $p->runner === 'cc');

$p = Parser::parseArgs(['kimi', ':anthropic:claude-3', '+0', 'test']);
assert_test('multi: runner', $p->runner === 'kimi');
assert_test('multi: provider', $p->provider === 'anthropic');
assert_test('multi: thinking 0', $p->thinking === 0);

// --- resolveCommand tests ---

$r = Parser::resolveCommand(Parser::parseArgs(['hello']));
assert_test('default runner: argv', $r['argv'] === ['opencode', 'run', 'hello']);
assert_test('default runner: env empty', $r['env'] === []);

$r = Parser::resolveCommand(Parser::parseArgs(['claude', 'fix']));
assert_test('claude runner: argv', $r['argv'] === ['claude', 'fix']);

$r = Parser::resolveCommand(Parser::parseArgs(['claude', '+3', 'think']));
assert_test('thinking flags: argv', $r['argv'] === ['claude', '--thinking', 'high', 'think']);

$r = Parser::resolveCommand(Parser::parseArgs(['claude', ':claude-3.5', 'go']));
assert_test('model flag: argv', $r['argv'] === ['claude', '--model', 'claude-3.5', 'go']);

$r = Parser::resolveCommand(Parser::parseArgs([':openai:gpt-4o', 'go']));
assert_test('provider env', $r['env'] === ['CCC_PROVIDER' => 'openai']);

try {
    Parser::resolveCommand(Parser::parseArgs([]));
    assert_test('empty prompt error', false);
} catch (\ValueError $e) {
    assert_test('empty prompt error', str_contains($e->getMessage(), 'empty'));
}

$r = Parser::resolveCommand(Parser::parseArgs(['kimi', '+4', 'max think']));
assert_test('kimi max thinking', $r['argv'] === ['kimi', '--think', 'max', 'max think']);

$r = Parser::resolveCommand(Parser::parseArgs(['oc', 'via abbrev']));
assert_test('oc abbreviation: argv', $r['argv'] === ['opencode', 'run', 'via abbrev']);

$cfg = new CccConfig();
$cfg->defaultThinking = 1;
$r = Parser::resolveCommand(Parser::parseArgs(['claude', 'think']), $cfg);
assert_test('config default thinking', $r['argv'] === ['claude', '--thinking', 'low', 'think']);

$cfg = new CccConfig();
$alias = new AliasDef();
$alias->runner = 'claude';
$alias->thinking = 2;
$alias->model = 'opus-4';
$cfg->aliases['work'] = $alias;
$r = Parser::resolveCommand(Parser::parseArgs(['@work', 'hello']), $cfg);
assert_test('alias: runner from alias', $r['argv'][0] === 'claude');
assert_test('alias: thinking from alias', in_array('--thinking', $r['argv']) && in_array('medium', $r['argv']));
assert_test('alias: model from alias', in_array('opus-4', $r['argv']));

$cfg = new CccConfig();
$cfg->defaultProvider = 'anthropic';
$r = Parser::resolveCommand(Parser::parseArgs(['hello']), $cfg);
assert_test('config default provider', $r['env'] === ['CCC_PROVIDER' => 'anthropic']);

$cfg = new CccConfig();
$cfg->defaultModel = 'sonnet-4';
$r = Parser::resolveCommand(Parser::parseArgs(['claude', 'hello']), $cfg);
assert_test('config default model', in_array('sonnet-4', $r['argv']));

$r = Parser::resolveCommand(Parser::parseArgs(['codex', ':my-model', 'go']));
assert_test('codex model flag', $r['argv'] === ['codex', '--model', 'my-model', 'go']);

$r = Parser::resolveCommand(Parser::parseArgs(['crush', 'hello']));
assert_test('crush no model flag', $r['argv'] === ['crush', 'hello']);

$warnings = [];
$r = Parser::resolveCommand(Parser::parseArgs(['@reviewer', 'hello']), null, $warnings);
assert_test('name fallback uses agent flag on opencode', $r['argv'] === ['opencode', 'run', '--agent', 'reviewer', 'hello']);
assert_test('name fallback on opencode has no warnings', $warnings === []);

$warnings = [];
$r = Parser::resolveCommand(Parser::parseArgs(['cc', '@reviewer', 'hello']), null, $warnings);
assert_test('name fallback uses agent flag on claude', $r['argv'] === ['claude', '--agent', 'reviewer', 'hello']);
assert_test('name fallback on claude has no warnings', $warnings === []);

$warnings = [];
$r = Parser::resolveCommand(Parser::parseArgs(['k', '@reviewer', 'hello']), null, $warnings);
assert_test('name fallback uses agent flag on kimi', $r['argv'] === ['kimi', '--agent', 'reviewer', 'hello']);
assert_test('name fallback on kimi has no warnings', $warnings === []);

$warnings = [];
$r = Parser::resolveCommand(Parser::parseArgs(['rc', '@reviewer', 'hello']), null, $warnings);
assert_test('name fallback warning on unsupported runner', $r['argv'] === ['codex', 'hello']);
assert_test('name fallback warning text', $warnings === ['warning: runner "rc" does not support agents; ignoring @reviewer']);

$cfg = new CccConfig();
$alias = new AliasDef();
$alias->agent = 'specialist';
$cfg->aliases['work'] = $alias;
$warnings = [];
$r = Parser::resolveCommand(Parser::parseArgs(['@work', 'hello']), $cfg, $warnings);
assert_test('preset agent wins over fallback', $r['argv'] === ['opencode', 'run', '--agent', 'specialist', 'hello']);
assert_test('preset agent has no warnings', $warnings === []);

$cfg = new CccConfig();
$alias = new AliasDef();
$alias->runner = 'claude';
$alias->agent = 'specialist';
$cfg->aliases['work'] = $alias;
$warnings = [];
$r = Parser::resolveCommand(Parser::parseArgs(['k', '@work', 'hello']), $cfg, $warnings);
assert_test('explicit runner overrides preset runner with agent retained', $r['argv'] === ['kimi', '--agent', 'specialist', 'hello']);
assert_test('explicit runner with preset agent has no warnings', $warnings === []);

echo "\n";
echo "Results: $passed passed, $failed failed\n";
exit($failed > 0 ? 1 : 0);

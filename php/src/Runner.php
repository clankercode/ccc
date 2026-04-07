<?php

namespace Call\Coding\Clis;

class Runner
{
    private $executor;

    public function __construct(?callable $executor = null)
    {
        $this->executor = $executor ?? self::class . '::defaultRun';
    }

    public function run(CommandSpec $spec): CompletedRun
    {
        return ($this->executor)($spec);
    }

    public function stream(CommandSpec $spec, callable $onEvent): CompletedRun
    {
        $result = $this->run($spec);
        if ($result->stdout !== '') {
            $onEvent('stdout', $result->stdout);
        }
        if ($result->stderr !== '') {
            $onEvent('stderr', $result->stderr);
        }
        return $result;
    }

    public static function defaultRun(CommandSpec $spec): CompletedRun
    {
        $argv = $spec->argv;
        $argv0 = $argv[0];

        $env = array_merge(getenv(), $spec->env);

        $descriptors = [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ];

        $origCwd = null;
        if ($spec->cwd !== null) {
            $origCwd = getcwd();
        }

        try {
            if ($spec->cwd !== null) {
                chdir($spec->cwd);
            }

            $proc = @proc_open($argv, $descriptors, $pipes, null, $env);

            if ($proc === false) {
                $error = error_get_last()['message'] ?? 'unknown error';
                self::restoreCwd($origCwd);
                return new CompletedRun($argv, 1, '', "failed to start $argv0: $error\n");
            }

            if ($spec->stdin_text !== null && strlen($spec->stdin_text) > 0) {
                fwrite($pipes[0], $spec->stdin_text);
            }
            fclose($pipes[0]);

            $stdout = stream_get_contents($pipes[1]);
            $stderr = stream_get_contents($pipes[2]);
            fclose($pipes[1]);
            fclose($pipes[2]);

            $exitCode = proc_close($proc);

            self::restoreCwd($origCwd);

            return new CompletedRun($argv, $exitCode, $stdout ?? '', $stderr ?? '');
        } catch (\Throwable $e) {
            self::restoreCwd($origCwd);
            $err = rtrim($e->getMessage());
            return new CompletedRun($argv, 1, '', "failed to start $argv0: $err\n");
        }
    }

    private static function restoreCwd(?string $origCwd): void
    {
        if ($origCwd !== null) {
            chdir($origCwd);
        }
    }
}

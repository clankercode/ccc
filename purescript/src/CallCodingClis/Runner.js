import { spawnSync } from "child_process";

export var runSyncImpl = function(spec) {
  return function() {
    var command = spec.argv[0];
    var args = spec.argv.slice(1);
    var options = { stdio: "pipe" };
    if (spec.stdinText !== null) options.input = spec.stdinText;
    if (spec.cwd !== null) options.cwd = spec.cwd;
    if (spec.env !== null) options.env = Object.assign({}, process.env, spec.env);

    var result = spawnSync(command, args, options);

    if (result.error) {
      return {
        argv: spec.argv,
        exitCode: 1,
        stdout: "",
        stderr: "failed to start " + command + ": " + result.error.message + "\n"
      };
    }

    return {
      argv: spec.argv,
      exitCode: result.status != null ? result.status : 1,
      stdout: result.stdout ? result.stdout.toString() : "",
      stderr: result.stderr ? result.stderr.toString() : ""
    };
  };
};

import { spawnSync } from "child_process";
import fs from "fs";
import path from "path";

function resolveOnPath(command, env) {
  if (command.includes("/")) return command;
  var searchPath = (env.PATH || process.env.PATH || "").split(":");
  for (var i = 0; i < searchPath.length; i += 1) {
    var candidate = path.join(searchPath[i], command);
    if (fs.existsSync(candidate)) return candidate;
  }
  return command;
}

function shebangFallback(command, args, env) {
  var resolved = resolveOnPath(command, env);
  if (!fs.existsSync(resolved)) return null;
  try {
    var firstLine = fs.readFileSync(resolved, "utf8").split(/\r?\n/, 1)[0];
    if (!firstLine.startsWith("#!")) return null;
    var parts = firstLine.slice(2).trim().split(/\s+/).filter(Boolean);
    if (parts.length === 0) return null;
    return {
      command: parts[0],
      args: parts.slice(1).concat([resolved], args)
    };
  } catch (_) {
    return null;
  }
}

export var runSyncImpl = function(spec) {
  return function() {
    var command = spec.argv[0];
    var args = spec.argv.slice(1);
    var options = { stdio: "pipe" };
    var env = spec.env !== null ? Object.assign({}, process.env, spec.env) : process.env;
    if (spec.stdinText !== null) options.input = spec.stdinText;
    if (spec.cwd !== null) options.cwd = spec.cwd;
    options.env = env;

    var result = spawnSync(command, args, options);
    if (result.error && (result.error.code === "EPERM" || result.error.code === "EACCES")) {
      var fallback = shebangFallback(command, args, env);
      if (fallback !== null) {
        command = fallback.command;
        args = fallback.args;
        result = spawnSync(command, args, options);
      }
    }

    if (result.error && result.status == null && result.stdout == null && result.stderr == null) {
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

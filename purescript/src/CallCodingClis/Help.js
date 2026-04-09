import { spawnSync } from "child_process";

export var which = function(binary) {
  return function() {
    try {
      spawnSync(binary, ["--version"], {
        stdio: "ignore",
        timeout: 3000,
      });
      return true;
    } catch (_) {
      return false;
    }
  };
};

export var getVersion = function(binary) {
  return function() {
    try {
      var result = spawnSync(binary, ["--version"], {
        stdio: "pipe",
        timeout: 3000,
      });
      if (result.status === 0 && result.stdout) {
        return result.stdout.toString().trim().split("\n")[0];
      }
      return "";
    } catch (_) {
      return "";
    }
  };
};

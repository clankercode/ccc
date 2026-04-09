import { which as whichSync } from "node:which";

export var which = function(binary) {
  return function() {
    try {
      whichSync(binary);
      return true;
    } catch (_) {
      return false;
    }
  };
};

export var getVersion = function(binary) {
  return function() {
    try {
      var child_process = require("child_process");
      var result = child_process.spawnSync(binary, ["--version"], {
        stdio: "pipe",
        timeout: 3000,
      });
      if (result.status === 0 && result.stdout) {
        var line = result.stdout.toString().trim().split("\n")[0];
        return line;
      }
      return "";
    } catch (_) {
      return "";
    }
  };
};

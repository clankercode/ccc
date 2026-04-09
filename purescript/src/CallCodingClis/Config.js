import { readFileSync, existsSync } from "fs";

export var readConfigImpl = function(path) {
  return function() {
    try {
      if (existsSync(path)) {
        return readFileSync(path, "utf8");
      }
    } catch (e) {}
    return "";
  };
};

export var xdgConfigHome = function() {
  return function() {
    return process.env.XDG_CONFIG_HOME || "";
  };
};

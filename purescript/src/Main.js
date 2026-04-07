export var writeStdout = function(s) {
  return function() {
    process.stdout.write(s);
  };
};

export var writeStderr = function(s) {
  return function() {
    process.stderr.write(s);
  };
};

export var processExit = function(code) {
  return function() {
    process.exit(code);
  };
};

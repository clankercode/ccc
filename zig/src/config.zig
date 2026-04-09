const std = @import("std");
const parser = @import("parser");

pub fn loadConfig(allocator: std.mem.Allocator, path: []const u8) !parser.CccConfig {
    var config = parser.CccConfig.init(allocator);
    errdefer config.deinit();

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == error.FileNotFound) return config;
        return err;
    };
    defer file.close();

    var current_section: enum { none, defaults, alias, abbrev } = .none;
    var current_alias_name: ?[]const u8 = null;
    var current_alias_def: parser.AliasDef = .{};
    const contents = try file.readToEndAlloc(allocator, 64 * 1024);
    config.contents = contents;

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (line[0] == '[') {
            if (current_section == .alias and current_alias_name != null) {
                try config.aliases.put(current_alias_name.?, current_alias_def);
                current_alias_name = null;
                current_alias_def = .{};
            }

            if (std.mem.eql(u8, line, "[defaults]")) {
                current_section = .defaults;
            } else if (std.mem.startsWith(u8, line, "[alias.") and line[line.len - 1] == ']') {
                const name = line[7 .. line.len - 1];
                current_alias_name = name;
                current_alias_def = .{};
                current_section = .alias;
            } else if ((std.mem.startsWith(u8, line, "[aliases.") and line[line.len - 1] == ']')) {
                const name = line[9 .. line.len - 1];
                current_alias_name = name;
                current_alias_def = .{};
                current_section = .alias;
            } else if (std.mem.eql(u8, line, "[abbrev]") or std.mem.eql(u8, line, "[abbreviations]")) {
                current_section = .abbrev;
            } else {
                current_section = .none;
            }
            continue;
        }

        const eq_pos = for (line, 0..) |c, i| {
            if (c == '=') break i;
        } else null;

        if (eq_pos) |ep| {
            const key = std.mem.trim(u8, line[0..ep], " \t");
            const val = unquoteValue(std.mem.trim(u8, line[ep + 1 ..], " \t"));

            switch (current_section) {
                .none => {
                    if (std.mem.eql(u8, key, "default_runner")) {
                        config.default_runner = val;
                    } else if (std.mem.eql(u8, key, "default_provider")) {
                        config.default_provider = val;
                    } else if (std.mem.eql(u8, key, "default_model")) {
                        config.default_model = val;
                    } else if (std.mem.eql(u8, key, "default_thinking")) {
                        config.default_thinking = std.fmt.parseInt(i32, val, 10) catch null;
                    }
                },
                .defaults => {
                    if (std.mem.eql(u8, key, "runner") or std.mem.eql(u8, key, "default_runner")) {
                        config.default_runner = val;
                    } else if (std.mem.eql(u8, key, "provider") or std.mem.eql(u8, key, "default_provider")) {
                        config.default_provider = val;
                    } else if (std.mem.eql(u8, key, "model") or std.mem.eql(u8, key, "default_model")) {
                        config.default_model = val;
                    } else if (std.mem.eql(u8, key, "thinking") or std.mem.eql(u8, key, "default_thinking")) {
                        config.default_thinking = std.fmt.parseInt(i32, val, 10) catch null;
                    }
                },
                .alias => {
                    if (std.mem.eql(u8, key, "runner")) {
                        current_alias_def.runner = val;
                    } else if (std.mem.eql(u8, key, "thinking")) {
                        current_alias_def.thinking = std.fmt.parseInt(i32, val, 10) catch null;
                    } else if (std.mem.eql(u8, key, "provider")) {
                        current_alias_def.provider = val;
                    } else if (std.mem.eql(u8, key, "model")) {
                        current_alias_def.model = val;
                    } else if (std.mem.eql(u8, key, "agent")) {
                        current_alias_def.agent = val;
                    }
                },
                .abbrev => {
                    try config.abbreviations.put(key, val);
                },
            }
        }
    }

    if (current_section == .alias and current_alias_name != null) {
        try config.aliases.put(current_alias_name.?, current_alias_def);
    }

    return config;
}

fn unquoteValue(val: []const u8) []const u8 {
    if (val.len < 2) return val;
    const first = val[0];
    const last = val[val.len - 1];
    if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) {
        return val[1 .. val.len - 1];
    }
    return val;
}

pub fn loadDefaultConfig(allocator: std.mem.Allocator) !parser.CccConfig {
    if (std.process.getEnvVarOwned(allocator, "CCC_CONFIG")) |path| {
        defer allocator.free(path);
        const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
            error.FileNotFound => null,
            else => return err,
        };
        if (stat) |info| {
            if (info.size > 0) {
                return loadConfig(allocator, path);
            }
        }
    } else |_| {}

    if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg| {
        defer allocator.free(xdg);
        if (try tryLoadJoinedPath(allocator, &.{ xdg, "ccc", "config" })) |config| return config;
        if (try tryLoadJoinedPath(allocator, &.{ xdg, "ccc", "config.toml" })) |config| return config;
    } else |_| {}

    if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        if (try tryLoadJoinedPath(allocator, &.{ home, ".config", "ccc", "config" })) |config| return config;
        if (try tryLoadJoinedPath(allocator, &.{ home, ".config", "ccc", "config.toml" })) |config| return config;
    } else |_| {}

    return parser.CccConfig.init(allocator);
}

fn tryLoadJoinedPath(
    allocator: std.mem.Allocator,
    parts: []const []const u8,
) !?parser.CccConfig {
    const path = try std.fs.path.join(allocator, parts);
    defer allocator.free(path);

    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    if (stat.kind != .file) return null;

    const config = try loadConfig(allocator, path);
    return config;
}

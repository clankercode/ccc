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

    var current_section: enum { none, alias, abbrev } = .none;
    var current_alias_name: ?[]const u8 = null;
    var current_alias_def: parser.AliasDef = .{};
    const contents = try file.readToEndAlloc(allocator, 64 * 1024);

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

            if (std.mem.startsWith(u8, line, "[alias.") and line[line.len - 1] == ']') {
                const name = line[7 .. line.len - 1];
                current_alias_name = name;
                current_alias_def = .{};
                current_section = .alias;
            } else if (std.mem.eql(u8, line, "[abbrev]")) {
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
            const val = std.mem.trim(u8, line[ep + 1 ..], " \t");

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
                .alias => {
                    if (std.mem.eql(u8, key, "runner")) {
                        current_alias_def.runner = val;
                    } else if (std.mem.eql(u8, key, "thinking")) {
                        current_alias_def.thinking = std.fmt.parseInt(i32, val, 10) catch null;
                    } else if (std.mem.eql(u8, key, "provider")) {
                        current_alias_def.provider = val;
                    } else if (std.mem.eql(u8, key, "model")) {
                        current_alias_def.model = val;
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

pub fn loadDefaultConfig(allocator: std.mem.Allocator) !parser.CccConfig {
    if (std.process.getEnvVarOwned(allocator, "CCC_CONFIG")) |path| {
        defer allocator.free(path);
        return loadConfig(allocator, path);
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

    return loadConfig(allocator, path) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
}

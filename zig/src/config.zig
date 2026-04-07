const std = @import("std");
const parser = @import("parser.zig");

pub fn loadConfig(allocator: std.mem.Allocator, path: []const u8) !parser.CccConfig {
    var config = parser.CccConfig.init(allocator);
    errdefer config.deinit();

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == error.FileNotFound) return config;
        return err;
    };
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    const reader = buf_reader.reader();

    var line_buf = std.ArrayList(u8).init(allocator);
    defer line_buf.deinit();

    var current_section: enum { none, alias, abbrev } = .none;
    var current_alias_name: ?[]const u8 = null;
    var current_alias_def: parser.AliasDef = .{};

    while (true) {
        line_buf.clearRetainingCapacity();
        reader.readUntilDelimiterArrayList(&line_buf, '\n', 4096) catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };

        const line = std.mem.trim(u8, line_buf.items, " \t\r");
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

const std = @import("std");

pub const RunnerInfo = struct {
    binary: []const u8,
    extra_args: []const []const u8,
    thinking_flags: [5]?[]const []const u8,
    provider_flag: []const u8,
    model_flag: []const u8,
};

pub const ParsedArgs = struct {
    runner: ?[]const u8 = null,
    thinking: ?i32 = null,
    provider: ?[]const u8 = null,
    model: ?[]const u8 = null,
    alias: ?[]const u8 = null,
    prompt: []const u8 = "",

    pub fn deinit(self: *ParsedArgs, allocator: std.mem.Allocator) void {
        if (self.runner) |r| allocator.free(r);
        if (self.prompt.len > 0) allocator.free(self.prompt);
    }
};

pub const AliasDef = struct {
    runner: ?[]const u8 = null,
    thinking: ?i32 = null,
    provider: ?[]const u8 = null,
    model: ?[]const u8 = null,
};

pub const CccConfig = struct {
    default_runner: []const u8 = "oc",
    default_provider: []const u8 = "",
    default_model: []const u8 = "",
    default_thinking: ?i32 = null,
    aliases: std.StringHashMap(AliasDef),
    abbreviations: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) CccConfig {
        return .{
            .aliases = std.StringHashMap(AliasDef).init(allocator),
            .abbreviations = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *CccConfig) void {
        self.aliases.deinit();
        self.abbreviations.deinit();
    }
};

pub const ResolvedCommand = struct {
    argv: []const []const u8,
    env: std.StringHashMap([]const u8),

    pub fn deinit(self: *ResolvedCommand, allocator: std.mem.Allocator) void {
        allocator.free(self.argv);
        self.env.deinit();
    }
};

pub const ResolveError = error{
    EmptyPrompt,
    OutOfMemory,
};

const opencode_info = RunnerInfo{
    .binary = "opencode",
    .extra_args = &.{"run"},
    .thinking_flags = .{ null, null, null, null, null },
    .provider_flag = "",
    .model_flag = "",
};

const claude_thinking_0 = &[_][]const u8{"--no-thinking"};
const claude_thinking_1 = &[_][]const u8{ "--thinking", "low" };
const claude_thinking_2 = &[_][]const u8{ "--thinking", "medium" };
const claude_thinking_3 = &[_][]const u8{ "--thinking", "high" };
const claude_thinking_4 = &[_][]const u8{ "--thinking", "max" };

const claude_info = RunnerInfo{
    .binary = "claude",
    .extra_args = &.{},
    .thinking_flags = .{
        claude_thinking_0,
        claude_thinking_1,
        claude_thinking_2,
        claude_thinking_3,
        claude_thinking_4,
    },
    .provider_flag = "",
    .model_flag = "--model",
};

const kimi_thinking_0 = &[_][]const u8{"--no-think"};
const kimi_thinking_1 = &[_][]const u8{ "--think", "low" };
const kimi_thinking_2 = &[_][]const u8{ "--think", "medium" };
const kimi_thinking_3 = &[_][]const u8{ "--think", "high" };
const kimi_thinking_4 = &[_][]const u8{ "--think", "max" };

const kimi_info = RunnerInfo{
    .binary = "kimi",
    .extra_args = &.{},
    .thinking_flags = .{
        kimi_thinking_0,
        kimi_thinking_1,
        kimi_thinking_2,
        kimi_thinking_3,
        kimi_thinking_4,
    },
    .provider_flag = "",
    .model_flag = "--model",
};

const codex_info = RunnerInfo{
    .binary = "codex",
    .extra_args = &.{},
    .thinking_flags = .{ null, null, null, null, null },
    .provider_flag = "",
    .model_flag = "--model",
};

const crush_info = RunnerInfo{
    .binary = "crush",
    .extra_args = &.{},
    .thinking_flags = .{ null, null, null, null, null },
    .provider_flag = "",
    .model_flag = "",
};

pub fn runnerRegistry(allocator: std.mem.Allocator) !std.StringHashMap(RunnerInfo) {
    var registry = std.StringHashMap(RunnerInfo).init(allocator);
    errdefer registry.deinit();

    try registry.put("opencode", opencode_info);
    try registry.put("claude", claude_info);
    try registry.put("kimi", kimi_info);
    try registry.put("codex", codex_info);
    try registry.put("crush", crush_info);

    try registry.put("oc", opencode_info);
    try registry.put("cc", claude_info);
    try registry.put("c", claude_info);
    try registry.put("k", kimi_info);
    try registry.put("rc", codex_info);
    try registry.put("cr", crush_info);

    return registry;
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}

fn isRunnerSelector(token: []const u8) bool {
    const names = .{
        "oc",       "cc",   "c",       "k",
        "rc",       "cr",   "codex",   "claude",
        "opencode", "kimi", "roocode", "crush",
        "pi",
    };
    inline for (names) |name| {
        if (eqlIgnoreCase(token, name)) return true;
    }
    return false;
}

fn matchThinking(token: []const u8) ?i32 {
    if (token.len != 2) return null;
    if (token[0] != '+') return null;
    const d = token[1];
    if (d >= '0' and d <= '4') return @as(i32, @intCast(d - '0'));
    return null;
}

fn isValidProviderChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-';
}

fn isValidModelChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '.' or c == '_' or c == '-';
}

fn isValidAliasChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-';
}

fn matchProviderModel(token: []const u8) ?struct { provider: []const u8, model: []const u8 } {
    if (token.len < 3) return null;
    if (token[0] != ':') return null;

    const rest = token[1..];
    for (rest, 0..) |ch, i| {
        if (ch == ':') {
            if (i == 0) return null;
            const provider = rest[0..i];
            const model = rest[i + 1 ..];
            if (model.len == 0) return null;
            for (provider) |c| {
                if (!isValidProviderChar(c)) return null;
            }
            for (model) |c| {
                if (!isValidModelChar(c)) return null;
            }
            return .{ .provider = provider, .model = model };
        }
    }
    return null;
}

fn matchModel(token: []const u8) ?[]const u8 {
    if (token.len < 2) return null;
    if (token[0] != ':') return null;
    const model = token[1..];
    if (model.len == 0) return null;
    for (model) |c| {
        if (!isValidModelChar(c)) return null;
    }
    return model;
}

fn matchAlias(token: []const u8) ?[]const u8 {
    if (token.len < 2) return null;
    if (token[0] != '@') return null;
    const name = token[1..];
    if (name.len == 0) return null;
    for (name) |c| {
        if (!isValidAliasChar(c)) return null;
    }
    return name;
}

fn allocLower(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const result = try allocator.alloc(u8, s.len);
    for (s, result) |c, *out| {
        out.* = std.ascii.toLower(c);
    }
    return result;
}

pub fn parseArgs(allocator: std.mem.Allocator, argv: []const []const u8) !ParsedArgs {
    var parsed = ParsedArgs{};
    var positional: std.ArrayList([]const u8) = .empty;
    defer positional.deinit(allocator);

    for (argv) |token| {
        if (isRunnerSelector(token) and parsed.runner == null and positional.items.len == 0) {
            parsed.runner = try allocLower(allocator, token);
        } else if (matchThinking(token)) |level| {
            if (positional.items.len == 0) {
                parsed.thinking = level;
            } else {
                try positional.append(allocator, token);
            }
        } else if (matchProviderModel(token)) |pm| {
            if (positional.items.len == 0) {
                parsed.provider = pm.provider;
                parsed.model = pm.model;
            } else {
                try positional.append(allocator, token);
            }
        } else if (matchModel(token)) |model| {
            if (positional.items.len == 0) {
                parsed.model = model;
            } else {
                try positional.append(allocator, token);
            }
        } else if (matchAlias(token)) |alias_name| {
            if (parsed.alias == null and positional.items.len == 0) {
                parsed.alias = alias_name;
            } else {
                try positional.append(allocator, token);
            }
        } else {
            try positional.append(allocator, token);
        }
    }

    parsed.prompt = try std.mem.join(allocator, " ", positional.items);
    return parsed;
}

fn resolveRunnerName(name: ?[]const u8, config: *const CccConfig) []const u8 {
    if (name) |n| {
        if (config.abbreviations.get(n)) |expanded| {
            return expanded;
        }
        return n;
    }
    return config.default_runner;
}

fn getRunnerInfoFromRegistry(registry: *const std.StringHashMap(RunnerInfo), name: []const u8) ?RunnerInfo {
    if (registry.get(name)) |info| return info;
    var iter = registry.iterator();
    while (iter.next()) |entry| {
        if (eqlIgnoreCase(name, entry.key_ptr.*)) return entry.value_ptr.*;
    }
    return null;
}

pub fn resolveCommand(allocator: std.mem.Allocator, parsed: ParsedArgs, config: *const CccConfig) ResolveError!ResolvedCommand {
    var registry = try runnerRegistry(allocator);
    defer registry.deinit();

    const runner_name = resolveRunnerName(parsed.runner, config);

    const info = getRunnerInfoFromRegistry(&registry, runner_name) orelse
        getRunnerInfoFromRegistry(&registry, config.default_runner) orelse
        opencode_info;

    var alias_def: ?AliasDef = null;
    if (parsed.alias) |a| {
        alias_def = config.aliases.get(a);
    }

    var effective_info = info;
    if (alias_def) |ad| {
        if (ad.runner != null and parsed.runner == null) {
            const alias_runner = resolveRunnerName(ad.runner, config);
            if (getRunnerInfoFromRegistry(&registry, alias_runner)) |ri| {
                effective_info = ri;
            }
        }
    }

    var argv: std.ArrayList([]const u8) = .empty;
    errdefer argv.deinit(allocator);

    try argv.append(allocator, effective_info.binary);
    try argv.appendSlice(allocator, effective_info.extra_args);

    var effective_thinking: ?i32 = parsed.thinking;
    if (effective_thinking == null) {
        if (alias_def) |ad| {
            effective_thinking = ad.thinking;
        }
    }
    if (effective_thinking == null) {
        effective_thinking = config.default_thinking;
    }
    if (effective_thinking) |level| {
        if (level >= 0 and level <= 4) {
            const idx: usize = @intCast(level);
            if (effective_info.thinking_flags[idx]) |flags| {
                try argv.appendSlice(allocator, flags);
            }
        }
    }

    var effective_provider: ?[]const u8 = parsed.provider;
    if (effective_provider == null) {
        if (alias_def) |ad| {
            effective_provider = ad.provider;
        }
    }
    if (effective_provider == null) {
        if (config.default_provider.len > 0) {
            effective_provider = config.default_provider;
        }
    }

    var effective_model: ?[]const u8 = parsed.model;
    if (effective_model == null) {
        if (alias_def) |ad| {
            effective_model = ad.model;
        }
    }
    if (effective_model == null) {
        if (config.default_model.len > 0) {
            effective_model = config.default_model;
        }
    }

    if (effective_model) |model| {
        if (effective_info.model_flag.len > 0) {
            try argv.append(allocator, effective_info.model_flag);
            try argv.append(allocator, model);
        }
    }

    const prompt = std.mem.trim(u8, parsed.prompt, " \t\n\r");
    if (prompt.len == 0) return error.EmptyPrompt;
    try argv.append(allocator, prompt);

    var env = std.StringHashMap([]const u8).init(allocator);
    errdefer env.deinit();

    if (effective_provider) |provider| {
        if (provider.len > 0) {
            try env.put("CCC_PROVIDER", provider);
        }
    }

    return .{
        .argv = try argv.toOwnedSlice(allocator),
        .env = env,
    };
}

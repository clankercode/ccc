const std = @import("std");
const help = @import("help");

test "help text uses @name and agent fallback" {
    try std.testing.expectEqualStrings(
        "usage: ccc [runner] [+thinking] [:provider:model] [@name] \"<Prompt>\"",
        help.USAGE_TEXT,
    );
    try std.testing.expect(std.mem.indexOf(u8, help.HELP_TEXT, "[@name]") != null);
    try std.testing.expect(
        std.mem.indexOf(u8, help.HELP_TEXT, "if no preset exists, treat it as an agent") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, help.HELP_TEXT, "codex (c/cx), roocode (rc)") != null,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, help.HELP_TEXT, "presets, abbreviations") != null,
    );
}

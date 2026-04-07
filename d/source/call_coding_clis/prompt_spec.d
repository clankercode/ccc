module call_coding_clis.prompt_spec;

import call_coding_clis.runner : CommandSpec;
import std.string : strip;

CommandSpec build_prompt_spec(string prompt) {
    if (prompt is null) {
        prompt = "";
    }
    auto trimmed = prompt.strip;
    if (trimmed.length == 0) {
        throw new Exception("prompt must not be empty");
    }
    return CommandSpec(["opencode", "run", trimmed]);
}

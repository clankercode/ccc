#define _XOPEN_SOURCE 700

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "../src/config.h"
#include "../src/parser.h"

static int test_count = 0;
static int pass_count = 0;

static void assert_str(const char *actual, const char *expected, const char *label) {
    test_count++;
    if (strcmp(actual, expected) == 0) {
        pass_count++;
    } else {
        fprintf(stderr, "FAIL %s: expected \"%s\", got \"%s\"\n", label, expected, actual);
    }
}

static void assert_int(int actual, int expected, const char *label) {
    test_count++;
    if (actual == expected) {
        pass_count++;
    } else {
        fprintf(stderr, "FAIL %s: expected %d, got %d\n", label, expected, actual);
    }
}

static void assert_ptr_null(const void *ptr, const char *label) {
    test_count++;
    if (ptr == NULL) {
        pass_count++;
    } else {
        fprintf(stderr, "FAIL %s: expected NULL\n", label);
    }
}

static void assert_ptr_not_null(const void *ptr, const char *label) {
    test_count++;
    if (ptr != NULL) {
        pass_count++;
    } else {
        fprintf(stderr, "FAIL %s: expected non-NULL\n", label);
    }
}

static int resolve_command_no_warning(
    ParsedArgs *parsed,
    CccConfig *config,
    const char *out_argv[],
    char *out_provider
) {
    return ccc_resolve_command(
        parsed,
        config,
        out_argv,
        CCC_MAX_ARGV,
        out_provider,
        128,
        NULL,
        0
    );
}

static void write_text_file(const char *path, const char *content) {
    FILE *fp = fopen(path, "w");
    if (fp == NULL) {
        fprintf(stderr, "failed to open %s\n", path);
        exit(1);
    }
    fputs(content, fp);
    fclose(fp);
}

static void join_path(char *out, size_t out_max, const char *left, const char *right) {
    size_t left_len = strlen(left);
    size_t right_len = strlen(right);
    if (left_len + right_len + 1 > out_max) {
        fprintf(stderr, "joined path too long\n");
        exit(1);
    }
    memcpy(out, left, left_len);
    memcpy(out + left_len, right, right_len + 1);
}

static void test_parse_prompt_only(void) {
    char *argv[] = {"ccc", "hello", "world"};
    ParsedArgs pa;
    ccc_parse_args(3, argv, &pa);
    assert_int(pa.has_runner, 0, "prompt-only: no runner");
    assert_int(pa.has_thinking, 0, "prompt-only: no thinking");
    assert_int(pa.has_provider, 0, "prompt-only: no provider");
    assert_int(pa.has_model, 0, "prompt-only: no model");
    assert_int(pa.has_alias, 0, "prompt-only: no alias");
    assert_str(pa.prompt, "hello world", "prompt-only: prompt");
}

static void test_parse_runner_selector(void) {
    char *argv[] = {"ccc", "claude", "fix", "bugs"};
    ParsedArgs pa;
    ccc_parse_args(4, argv, &pa);
    assert_int(pa.has_runner, 1, "runner-sel: has runner");
    assert_str(pa.runner, "claude", "runner-sel: runner");
    assert_str(pa.prompt, "fix bugs", "runner-sel: prompt");
}

static void test_parse_runner_abbrev(void) {
    char *argv[] = {"ccc", "CC", "hello"};
    ParsedArgs pa;
    ccc_parse_args(3, argv, &pa);
    assert_int(pa.has_runner, 1, "runner-abbrev: has runner");
    assert_str(pa.runner, "cc", "runner-abbrev: runner lowercase");
}

static void test_parse_thinking(void) {
    char *argv[] = {"ccc", "+3", "hello"};
    ParsedArgs pa;
    ccc_parse_args(3, argv, &pa);
    assert_int(pa.has_thinking, 1, "thinking: has thinking");
    assert_int(pa.thinking, 3, "thinking: level");
    assert_str(pa.prompt, "hello", "thinking: prompt");
}

static void test_parse_thinking_zero(void) {
    char *argv[] = {"ccc", "+0", "hello"};
    ParsedArgs pa;
    ccc_parse_args(3, argv, &pa);
    assert_int(pa.has_thinking, 1, "thinking-zero: has thinking");
    assert_int(pa.thinking, 0, "thinking-zero: level 0");
}

static void test_parse_provider_model(void) {
    char *argv[] = {"ccc", ":anthropic:claude-3.5-sonnet", "hello"};
    ParsedArgs pa;
    ccc_parse_args(3, argv, &pa);
    assert_int(pa.has_provider, 1, "prov-model: has provider");
    assert_int(pa.has_model, 1, "prov-model: has model");
    assert_str(pa.provider, "anthropic", "prov-model: provider");
    assert_str(pa.model, "claude-3.5-sonnet", "prov-model: model");
}

static void test_parse_model_only(void) {
    char *argv[] = {"ccc", ":sonnet-4", "hello"};
    ParsedArgs pa;
    ccc_parse_args(3, argv, &pa);
    assert_int(pa.has_model, 1, "model-only: has model");
    assert_int(pa.has_provider, 0, "model-only: no provider");
    assert_str(pa.model, "sonnet-4", "model-only: model");
}

static void test_parse_alias(void) {
    char *argv[] = {"ccc", "@work", "hello"};
    ParsedArgs pa;
    ccc_parse_args(3, argv, &pa);
    assert_int(pa.has_alias, 1, "alias: has alias");
    assert_str(pa.alias, "work", "alias: name");
}

static void test_parse_positionals_stop_flags(void) {
    char *argv[] = {"ccc", "hello", "+3"};
    ParsedArgs pa;
    ccc_parse_args(3, argv, &pa);
    assert_int(pa.has_thinking, 0, "pos-stop: no thinking after positional");
    assert_str(pa.prompt, "hello +3", "pos-stop: +3 is positional");
}

static void test_parse_full_combo(void) {
    char *argv[] = {"ccc", "claude", "+2", ":anthropic:sonnet", "fix", "it"};
    ParsedArgs pa;
    ccc_parse_args(6, argv, &pa);
    assert_str(pa.runner, "claude", "combo: runner");
    assert_int(pa.thinking, 2, "combo: thinking");
    assert_str(pa.provider, "anthropic", "combo: provider");
    assert_str(pa.model, "sonnet", "combo: model");
    assert_str(pa.prompt, "fix it", "combo: prompt");
}

static void test_resolve_default_runner(void) {
    char *argv[] = {"ccc", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    ccc_parse_args(2, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    int c = resolve_command_no_warning(&pa, &cfg, out, prov);
    assert_int(c, 3, "resolve-default: argc");
    assert_str(out[0], "opencode", "resolve-default: binary");
    assert_str(out[1], "run", "resolve-default: extra");
    assert_str(out[2], "hello", "resolve-default: prompt");
}

static void test_resolve_claude_runner(void) {
    char *argv[] = {"ccc", "claude", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    ccc_parse_args(3, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    int c = resolve_command_no_warning(&pa, &cfg, out, prov);
    assert_int(c, 2, "resolve-claude: argc");
    assert_str(out[0], "claude", "resolve-claude: binary");
    assert_str(out[1], "hello", "resolve-claude: prompt");
}

static void test_resolve_thinking_flags(void) {
    char *argv[] = {"ccc", "claude", "+2", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    ccc_parse_args(4, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    int c = resolve_command_no_warning(&pa, &cfg, out, prov);
    assert_int(c, 4, "resolve-thinking: argc");
    assert_str(out[0], "claude", "resolve-thinking: binary");
    assert_str(out[1], "--thinking", "resolve-thinking: flag");
    assert_str(out[2], "medium", "resolve-thinking: level");
    assert_str(out[3], "hello", "resolve-thinking: prompt");
}

static void test_resolve_thinking_zero(void) {
    char *argv[] = {"ccc", "claude", "+0", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    ccc_parse_args(4, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    int c = resolve_command_no_warning(&pa, &cfg, out, prov);
    assert_int(c, 3, "resolve-thinking0: argc");
    assert_str(out[1], "--no-thinking", "resolve-thinking0: flag");
}

static void test_resolve_model_flag(void) {
    char *argv[] = {"ccc", "claude", ":sonnet", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    ccc_parse_args(4, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    int c = resolve_command_no_warning(&pa, &cfg, out, prov);
    assert_int(c, 4, "resolve-model: argc");
    assert_str(out[1], "--model", "resolve-model: flag");
    assert_str(out[2], "sonnet", "resolve-model: model");
    assert_str(out[3], "hello", "resolve-model: prompt");
}

static void test_resolve_provider_env(void) {
    char *argv[] = {"ccc", ":anthropic:sonnet", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    ccc_parse_args(3, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    resolve_command_no_warning(&pa, &cfg, out, prov);
    assert_str(prov, "anthropic", "resolve-provider: env");
}

static void test_resolve_empty_prompt_error(void) {
    char *argv[] = {"ccc"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    ccc_parse_args(1, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    int c = resolve_command_no_warning(&pa, &cfg, out, prov);
    assert_int(c, -1, "resolve-empty: returns -1");
}

static void test_resolve_config_defaults(void) {
    char *argv[] = {"ccc", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    strncpy(cfg.default_runner, "claude", sizeof(cfg.default_runner) - 1);
    strncpy(cfg.default_model, "test-model", sizeof(cfg.default_model) - 1);
    strncpy(cfg.default_provider, "test-provider", sizeof(cfg.default_provider) - 1);
    ccc_parse_args(2, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    int c = resolve_command_no_warning(&pa, &cfg, out, prov);
    assert_int(c, 4, "resolve-cfg-defaults: argc");
    assert_str(out[1], "--model", "resolve-cfg-defaults: model flag");
    assert_str(out[2], "test-model", "resolve-cfg-defaults: model val");
    assert_str(prov, "test-provider", "resolve-cfg-defaults: provider");
}

static void test_resolve_alias_runner(void) {
    char *argv[] = {"ccc", "@fast", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    AliasDef *ad = &cfg.aliases[cfg.alias_count++];
    memset(ad, 0, sizeof(*ad));
    strncpy(ad->name, "fast", sizeof(ad->name) - 1);
    strncpy(ad->runner, "claude", sizeof(ad->runner) - 1);
    ad->has_runner = 1;
    ccc_parse_args(3, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    int c = resolve_command_no_warning(&pa, &cfg, out, prov);
    assert_int(c, 2, "resolve-alias: argc");
    assert_str(out[0], "claude", "resolve-alias: binary");
}

static void test_get_runner_registry(void) {
    assert_ptr_not_null(ccc_get_runner("opencode"), "registry: opencode");
    assert_ptr_not_null(ccc_get_runner("oc"), "registry: oc");
    assert_ptr_not_null(ccc_get_runner("claude"), "registry: claude");
    assert_ptr_not_null(ccc_get_runner("cc"), "registry: cc");
    assert_ptr_not_null(ccc_get_runner("c"), "registry: c");
    assert_ptr_not_null(ccc_get_runner("kimi"), "registry: kimi");
    assert_ptr_not_null(ccc_get_runner("k"), "registry: k");
    assert_ptr_not_null(ccc_get_runner("codex"), "registry: codex");
    assert_ptr_not_null(ccc_get_runner("rc"), "registry: rc");
    assert_ptr_not_null(ccc_get_runner("crush"), "registry: crush");
    assert_ptr_not_null(ccc_get_runner("cr"), "registry: cr");
    assert_ptr_null(ccc_get_runner("unknown"), "registry: unknown");
    assert_ptr_null(ccc_get_runner(NULL), "registry: null");
}

static void test_resolve_abbreviation(void) {
    char *argv[] = {"ccc", "oc", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    strncpy(cfg.abbreviations[0].from, "oc", sizeof(cfg.abbreviations[0].from) - 1);
    strncpy(cfg.abbreviations[0].to, "claude", sizeof(cfg.abbreviations[0].to) - 1);
    cfg.abbrev_count = 1;
    ccc_parse_args(3, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    int c = resolve_command_no_warning(&pa, &cfg, out, prov);
    assert_int(c, 2, "resolve-abbrev: argc");
    assert_str(out[0], "claude", "resolve-abbrev: binary");
}

static void test_resolve_opencode_no_thinking(void) {
    char *argv[] = {"ccc", "oc", "+2", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    ccc_parse_args(4, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    int c = resolve_command_no_warning(&pa, &cfg, out, prov);
    assert_int(c, 3, "resolve-oc-nothink: argc");
    assert_str(out[0], "opencode", "resolve-oc-nothink: binary");
    assert_str(out[1], "run", "resolve-oc-nothink: extra");
    assert_str(out[2], "hello", "resolve-oc-nothink: prompt");
}

static void test_resolve_agent_fallback(void) {
    char *argv[] = {"ccc", "@reviewer", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    ccc_parse_args(3, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    char warnings[1][CCC_MAX_WARNING_LEN] = {{0}};
    int c = ccc_resolve_command(
        &pa,
        &cfg,
        out,
        CCC_MAX_ARGV,
        prov,
        (int)sizeof(prov),
        warnings,
        1
    );
    assert_int(c, 5, "resolve-agent-fallback: argc");
    assert_str(out[0], "opencode", "resolve-agent-fallback: binary");
    assert_str(out[1], "run", "resolve-agent-fallback: extra");
    assert_str(out[2], "--agent", "resolve-agent-fallback: flag");
    assert_str(out[3], "reviewer", "resolve-agent-fallback: agent");
    assert_str(out[4], "hello", "resolve-agent-fallback: prompt");
    assert_str(warnings[0], "", "resolve-agent-fallback: warning");
}

static void test_resolve_preset_agent(void) {
    char *argv[] = {"ccc", "@reviewer", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    AliasDef *ad = &cfg.aliases[cfg.alias_count++];
    memset(ad, 0, sizeof(*ad));
    strncpy(ad->name, "reviewer", sizeof(ad->name) - 1);
    strncpy(ad->agent, "specialist", sizeof(ad->agent) - 1);
    ad->has_agent = 1;
    ccc_parse_args(3, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    char warnings[1][CCC_MAX_WARNING_LEN] = {{0}};
    int c = ccc_resolve_command(
        &pa,
        &cfg,
        out,
        CCC_MAX_ARGV,
        prov,
        (int)sizeof(prov),
        warnings,
        1
    );
    assert_int(c, 5, "resolve-preset-agent: argc");
    assert_str(out[0], "opencode", "resolve-preset-agent: binary");
    assert_str(out[1], "run", "resolve-preset-agent: extra");
    assert_str(out[2], "--agent", "resolve-preset-agent: flag");
    assert_str(out[3], "specialist", "resolve-preset-agent: agent");
    assert_str(out[4], "hello", "resolve-preset-agent: prompt");
    assert_str(warnings[0], "", "resolve-preset-agent: warning");
}

static void test_resolve_unsupported_agent_warning(void) {
    char *argv[] = {"ccc", "codex", "@reviewer", "hello"};
    ParsedArgs pa;
    CccConfig cfg;
    ccc_init_config(&cfg);
    ccc_parse_args(4, argv, &pa);

    const char *out[CCC_MAX_ARGV];
    char prov[128] = {0};
    char warnings[1][CCC_MAX_WARNING_LEN] = {{0}};
    int c = ccc_resolve_command(
        &pa,
        &cfg,
        out,
        CCC_MAX_ARGV,
        prov,
        (int)sizeof(prov),
        warnings,
        1
    );
    assert_int(c, 2, "resolve-unsupported-agent: argc");
    assert_str(out[0], "codex", "resolve-unsupported-agent: binary");
    assert_str(out[1], "hello", "resolve-unsupported-agent: prompt");
    assert_str(
        warnings[0],
        "warning: runner \"codex\" does not support agents; ignoring @reviewer",
        "resolve-unsupported-agent: warning"
    );
}

static void test_load_config_defaults_aliases_and_abbreviations(void) {
    char root_template[] = "./build/ccc-config-load-XXXXXX";
    char *root = mkdtemp(root_template);
    if (root == NULL) {
        fprintf(stderr, "failed to create temp config root\n");
        exit(1);
    }

    char config_dir[4096];
    join_path(config_dir, sizeof(config_dir), root, "/ccc");
    if (mkdir(config_dir, 0700) != 0) {
        fprintf(stderr, "failed to create config dir %s\n", config_dir);
        exit(1);
    }

    char config_path[4096];
    join_path(config_path, sizeof(config_path), config_dir, "/config.toml");
    write_text_file(
        config_path,
        "[defaults]\n"
        "runner = \"claude\"\n"
        "provider = \"anthropic\"\n"
        "model = \"claude-sonnet\"\n"
        "thinking = 3\n"
        "\n"
        "[aliases.reviewer]\n"
        "runner = \"kimi\"\n"
        "thinking = 2\n"
        "provider = \"groq\"\n"
        "model = \"kimi-k2\"\n"
        "agent = \"specialist\"\n"
        "\n"
        "[abbreviations]\n"
        "oc = \"claude\"\n"
        "k = \"kimi\"\n"
    );

    CccConfig cfg;
    if (ccc_load_config(config_path, &cfg) != 0) {
        fprintf(stderr, "failed to load config file\n");
        exit(1);
    }

    assert_str(cfg.default_runner, "claude", "load-config: default runner");
    assert_str(cfg.default_provider, "anthropic", "load-config: default provider");
    assert_str(cfg.default_model, "claude-sonnet", "load-config: default model");
    assert_int(cfg.has_default_thinking, 1, "load-config: default thinking flag");
    assert_int(cfg.default_thinking, 3, "load-config: default thinking");
    assert_int(cfg.alias_count, 1, "load-config: alias count");
    assert_str(cfg.aliases[0].name, "reviewer", "load-config: alias name");
    assert_str(cfg.aliases[0].runner, "kimi", "load-config: alias runner");
    assert_int(cfg.aliases[0].has_agent, 1, "load-config: alias agent flag");
    assert_str(cfg.aliases[0].agent, "specialist", "load-config: alias agent");
    assert_int(cfg.abbrev_count, 2, "load-config: abbrev count");
    assert_str(cfg.abbreviations[0].from, "oc", "load-config: abbrev 1 from");
    assert_str(cfg.abbreviations[0].to, "claude", "load-config: abbrev 1 to");
    assert_str(cfg.abbreviations[1].from, "k", "load-config: abbrev 2 from");
    assert_str(cfg.abbreviations[1].to, "kimi", "load-config: abbrev 2 to");
}

static void test_find_config_path_prefers_xdg(void) {
    char xdg_template[] = "./build/ccc-xdg-config-XXXXXX";
    char home_template[] = "./build/ccc-home-config-XXXXXX";
    char *xdg_root = mkdtemp(xdg_template);
    char *home_root = mkdtemp(home_template);
    if (xdg_root == NULL || home_root == NULL) {
        fprintf(stderr, "failed to create temp config roots\n");
        exit(1);
    }

    char xdg_dir[4096];
    join_path(xdg_dir, sizeof(xdg_dir), xdg_root, "/ccc");
    if (mkdir(xdg_dir, 0700) != 0) {
        fprintf(stderr, "failed to create xdg config dir %s\n", xdg_dir);
        exit(1);
    }
    char xdg_path[4096];
    join_path(xdg_path, sizeof(xdg_path), xdg_dir, "/config.toml");
    write_text_file(xdg_path, "[defaults]\nrunner = \"claude\"\n");

    char home_config_dir[4096];
    join_path(home_config_dir, sizeof(home_config_dir), home_root, "/.config");
    if (mkdir(home_config_dir, 0700) != 0) {
        fprintf(stderr, "failed to create home config base dir %s\n", home_config_dir);
        exit(1);
    }
    char home_ccc_dir[4096];
    join_path(home_ccc_dir, sizeof(home_ccc_dir), home_config_dir, "/ccc");
    if (mkdir(home_ccc_dir, 0700) != 0) {
        fprintf(stderr, "failed to create home ccc dir %s\n", home_ccc_dir);
        exit(1);
    }
    char home_path[4096];
    join_path(home_path, sizeof(home_path), home_ccc_dir, "/config.toml");
    write_text_file(home_path, "[defaults]\nrunner = \"kimi\"\n");

    char resolved[4096] = {0};
    int ok = ccc_find_config_path(NULL, xdg_root, home_root, resolved, sizeof(resolved));
    assert_int(ok, 1, "find-config: success");
    assert_str(resolved, xdg_path, "find-config: prefers xdg");
}

int main(void) {
    test_parse_prompt_only();
    test_parse_runner_selector();
    test_parse_runner_abbrev();
    test_parse_thinking();
    test_parse_thinking_zero();
    test_parse_provider_model();
    test_parse_model_only();
    test_parse_alias();
    test_parse_positionals_stop_flags();
    test_parse_full_combo();
    test_resolve_default_runner();
    test_resolve_claude_runner();
    test_resolve_thinking_flags();
    test_resolve_thinking_zero();
    test_resolve_model_flag();
    test_resolve_provider_env();
    test_resolve_empty_prompt_error();
    test_resolve_config_defaults();
    test_resolve_alias_runner();
    test_get_runner_registry();
    test_resolve_abbreviation();
    test_resolve_opencode_no_thinking();
    test_resolve_agent_fallback();
    test_resolve_preset_agent();
    test_resolve_unsupported_agent_warning();
    test_load_config_defaults_aliases_and_abbreviations();
    test_find_config_path_prefers_xdg();

    printf("parser: %d/%d passed\n", pass_count, test_count);
    return pass_count == test_count ? 0 : 1;
}

#include "config.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static int path_exists(const char *path) {
    struct stat st;
    return path != NULL && path[0] != '\0' && stat(path, &st) == 0;
}

static int copy_path(char *out_path, int out_max, const char *path) {
    size_t len;
    if (out_path == NULL || out_max <= 0 || path == NULL) return 0;
    len = strlen(path);
    if (len >= (size_t)out_max) return 0;
    memcpy(out_path, path, len + 1);
    return 1;
}

int ccc_find_config_path(
    const char *ccc_config,
    const char *xdg_config_home,
    const char *home,
    char *out_path,
    size_t out_max
) {
    char candidate[512];

    (void)ccc_config;

    if (out_path == NULL || out_max == 0) {
        return 0;
    }
    out_path[0] = '\0';

    if (xdg_config_home != NULL && xdg_config_home[0] != '\0') {
        if (snprintf(candidate, sizeof(candidate), "%s/ccc/config.toml", xdg_config_home) < (int)sizeof(candidate) &&
            path_exists(candidate) && copy_path(out_path, (int)out_max, candidate)) {
            return 1;
        }
    }

    if (home != NULL && home[0] != '\0') {
        if (snprintf(candidate, sizeof(candidate), "%s/.config/ccc/config.toml", home) < (int)sizeof(candidate) &&
            path_exists(candidate) && copy_path(out_path, (int)out_max, candidate)) {
            return 1;
        }
    }

    return 0;
}

static void trim_str(char *str) {
    char *start = str;
    while (*start && isspace((unsigned char)*start)) start++;
    if (start != str) {
        memmove(str, start, strlen(start) + 1);
    }
    size_t len = strlen(str);
    while (len > 0 && isspace((unsigned char)str[len - 1])) {
        len--;
    }
    str[len] = '\0';
}

static void strip_quotes(char *str) {
    size_t len = strlen(str);
    if (len >= 2 &&
        ((str[0] == '"' && str[len - 1] == '"') || (str[0] == '\'' && str[len - 1] == '\''))) {
        memmove(str, str + 1, len - 2);
        str[len - 2] = '\0';
    }
}

static int parse_kv(const char *line, char *key, int key_max, char *val, int val_max) {
    const char *eq = strchr(line, '=');
    if (eq == NULL) return 0;
    size_t klen = (size_t)(eq - line);
    size_t vlen = strlen(eq + 1);
    if (klen == 0 || klen >= (size_t)key_max || vlen >= (size_t)val_max) return 0;
    memcpy(key, line, klen);
    key[klen] = '\0';
    memcpy(val, eq + 1, vlen + 1);
    trim_str(key);
    trim_str(val);
    strip_quotes(val);
    return 1;
}

int ccc_load_config(const char *path, CccConfig *out) {
    if (out == NULL) return -1;
    ccc_init_config(out);

    if (path == NULL || path[0] == '\0') return -1;

    FILE *fp = fopen(path, "r");
    if (fp == NULL) return -1;

    char line[1024];
    int section = 0;
    char section_name[128] = {0};

    while (fgets(line, sizeof(line), fp) != NULL) {
        trim_str(line);
        if (line[0] == '\0' || line[0] == '#') continue;

        if (line[0] == '[') {
            char *end = strchr(line, ']');
            if (end == NULL) continue;
            *end = '\0';
            const char *inner = line + 1;
            if (strcmp(inner, "defaults") == 0) {
                section = 3;
            } else if (strncmp(inner, "aliases.", 8) == 0) {
                section = 1;
                size_t nlen = strlen(inner + 8);
                if (nlen >= sizeof(section_name)) nlen = sizeof(section_name) - 1;
                memcpy(section_name, inner + 8, nlen);
                section_name[nlen] = '\0';
            } else if (strncmp(inner, "alias.", 6) == 0) {
                section = 1;
                size_t nlen = strlen(inner + 6);
                if (nlen >= sizeof(section_name)) nlen = sizeof(section_name) - 1;
                memcpy(section_name, inner + 6, nlen);
                section_name[nlen] = '\0';
            } else if (strcmp(inner, "abbrev") == 0 || strcmp(inner, "abbreviations") == 0) {
                section = 2;
            } else {
                section = 0;
            }
            continue;
        }

        char key[256], val[512];
        if (!parse_kv(line, key, (int)sizeof(key), val, (int)sizeof(val))) continue;

        if (section == 0) {
            if (strcmp(key, "default_runner") == 0) {
                strncpy(out->default_runner, val, sizeof(out->default_runner) - 1);
            } else if (strcmp(key, "default_provider") == 0) {
                strncpy(out->default_provider, val, sizeof(out->default_provider) - 1);
            } else if (strcmp(key, "default_model") == 0) {
                strncpy(out->default_model, val, sizeof(out->default_model) - 1);
            } else if (strcmp(key, "default_thinking") == 0) {
                out->default_thinking = atoi(val);
                out->has_default_thinking = 1;
            }
        } else if (section == 3) {
            if (strcmp(key, "runner") == 0) {
                strncpy(out->default_runner, val, sizeof(out->default_runner) - 1);
            } else if (strcmp(key, "provider") == 0) {
                strncpy(out->default_provider, val, sizeof(out->default_provider) - 1);
            } else if (strcmp(key, "model") == 0) {
                strncpy(out->default_model, val, sizeof(out->default_model) - 1);
            } else if (strcmp(key, "thinking") == 0) {
                out->default_thinking = atoi(val);
                out->has_default_thinking = 1;
            }
        } else if (section == 1) {
            if (out->alias_count >= CCC_MAX_ALIASES ||
                (out->alias_count == 0 && strcmp(out->aliases[0].name, section_name) != 0) ||
                (out->alias_count > 0 && strcmp(out->aliases[out->alias_count - 1].name, section_name) != 0)) {
                AliasDef *ad = &out->aliases[out->alias_count];
                memset(ad, 0, sizeof(*ad));
                strncpy(ad->name, section_name, sizeof(ad->name) - 1);
                out->alias_count++;
            }
            AliasDef *ad = &out->aliases[out->alias_count - 1];
            if (strcmp(key, "runner") == 0) {
                strncpy(ad->runner, val, sizeof(ad->runner) - 1);
                ad->has_runner = 1;
            } else if (strcmp(key, "thinking") == 0) {
                ad->thinking = atoi(val);
                ad->has_thinking = 1;
            } else if (strcmp(key, "provider") == 0) {
                strncpy(ad->provider, val, sizeof(ad->provider) - 1);
                ad->has_provider = 1;
            } else if (strcmp(key, "model") == 0) {
                strncpy(ad->model, val, sizeof(ad->model) - 1);
                ad->has_model = 1;
            } else if (strcmp(key, "agent") == 0) {
                strncpy(ad->agent, val, sizeof(ad->agent) - 1);
                ad->has_agent = 1;
            }
        } else if (section == 2) {
            if (out->abbrev_count < CCC_MAX_ABBREVS) {
                strncpy(out->abbreviations[out->abbrev_count].from, key,
                        sizeof(out->abbreviations[out->abbrev_count].from) - 1);
                strncpy(out->abbreviations[out->abbrev_count].to, val,
                        sizeof(out->abbreviations[out->abbrev_count].to) - 1);
                out->abbrev_count++;
            }
        }
    }

    fclose(fp);
    return 0;
}

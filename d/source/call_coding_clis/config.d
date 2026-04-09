module call_coding_clis.config;

import std.stdio : File;
import std.file : exists, isFile, getSize;
import std.string : strip, chomp, split, indexOf;
import std.conv : to;
import std.typecons : Nullable;

import call_coding_clis.parser : CccConfig, AliasDef;

CccConfig loadConfig(string path) {
    CccConfig config;

    if (path is null || path.length == 0) {
        return config;
    }

    string section;
    string subkey;

    try {
        auto f = File(path, "r");
        scope (exit) f.close();

        foreach (line; f.byLine()) {
            auto l = line.strip;
            if (l.length == 0 || l[0] == '#') continue;

            if (l[0] == '[') {
                auto end = indexOf(l, ']');
                if (end < 0) continue;
                auto sec = l[1 .. end].strip;

                auto dot = indexOf(sec, '.');
                if (dot >= 0) {
                    section = sec[0 .. dot].idup;
                    subkey = sec[dot + 1 .. $].idup;
                } else {
                    section = sec.idup;
                    subkey = "";
                }
                continue;
            }

            auto eq = indexOf(l, '=');
            if (eq < 0) continue;

            auto key = l[0 .. eq].strip.idup;
            auto val = l[eq + 1 .. $].strip.idup;

            if (val.length >= 2 && val[0] == '"' && val[$ - 1] == '"') {
                val = val[1 .. $ - 1].idup;
            }

            if (section == "") {
                switch (key) {
                    case "default_runner":
                        config.defaultRunner = val;
                        break;
                    case "default_provider":
                        config.defaultProvider = val;
                        break;
                    case "default_model":
                        config.defaultModel = val;
                        break;
                    case "default_thinking":
                        config.defaultThinking = Nullable!int(to!int(val));
                        break;
                    default:
                        break;
                }
            } else if (section == "defaults") {
                switch (key) {
                    case "runner":
                        config.defaultRunner = val;
                        break;
                    case "provider":
                        config.defaultProvider = val;
                        break;
                    case "model":
                        config.defaultModel = val;
                        break;
                    case "thinking":
                        config.defaultThinking = Nullable!int(to!int(val));
                        break;
                    default:
                        break;
                }
            } else if (section == "abbreviations") {
                config.abbreviations[key] = val;
            } else if (section == "aliases" && subkey.length > 0) {
                auto def_ = subkey in config.aliases;
                if (def_ is null) {
                    config.aliases[subkey] = AliasDef();
                    def_ = subkey in config.aliases;
                }
                switch (key) {
                    case "runner":
                        (*def_).runner = Nullable!string(val);
                        break;
                    case "thinking":
                        (*def_).thinking = Nullable!int(to!int(val));
                        break;
                    case "provider":
                        (*def_).provider = Nullable!string(val);
                        break;
                    case "model":
                        (*def_).model = Nullable!string(val);
                        break;
                    case "agent":
                        (*def_).agent = Nullable!string(val);
                        break;
                    default:
                        break;
                }
            }
        }
    } catch (Exception) {
        return CccConfig();
    }

    return config;
}

string findConfigPath(string cccConfig, string xdgConfigHome, string home) {
    if (cccConfig.length > 0 && exists(cccConfig) && isFile(cccConfig) && getSize(cccConfig) > 0) {
        return cccConfig;
    }
    if (xdgConfigHome.length > 0) {
        return xdgConfigHome ~ "/ccc/config.toml";
    }
    if (home.length > 0) {
        return home ~ "/.config/ccc/config.toml";
    }
    return "";
}

unittest {
    import std.stdio : File;
    import std.file : tempDir, remove;

    auto tmpPath = tempDir ~ "/ccc_d_config_agent.toml";
    {
        auto f = File(tmpPath, "w");
        scope(exit) f.close();
        f.writeln(`[aliases.work]`);
        f.writeln(`runner = "oc"`);
        f.writeln(`thinking = 1`);
        f.writeln(`agent = "reviewer"`);
    }

    auto config = loadConfig(tmpPath);
    assert("work" in config.aliases);
    assert(config.aliases["work"].runner.get == "oc");
    assert(config.aliases["work"].thinking.get == 1);
    assert(config.aliases["work"].agent.get == "reviewer");

    remove(tmpPath);
}

unittest {
    import std.stdio : File;
    import std.file : tempDir, mkdirRecurse, write, remove;

    auto tmpRoot = tempDir ~ "/ccc_d_config_path";
    auto legacy = tmpRoot ~ "/legacy-config";
    auto xdgRoot = tmpRoot ~ "/xdg";
    auto homeRoot = tmpRoot ~ "/home";
    mkdirRecurse(xdgRoot ~ "/ccc");
    mkdirRecurse(homeRoot ~ "/.config/ccc");

    {
        auto f = File(legacy, "w");
        scope(exit) f.close();
    }
    write(xdgRoot ~ "/ccc/config.toml", `[defaults]
runner = "claude"
`);
    write(homeRoot ~ "/.config/ccc/config.toml", `[defaults]
runner = "kimi"
`);

    assert(findConfigPath(legacy, xdgRoot, homeRoot) == xdgRoot ~ "/ccc/config.toml");

    write(legacy, `[defaults]
runner = "oc"
`);
    assert(findConfigPath(legacy, xdgRoot, homeRoot) == legacy);

    remove(legacy);
    remove(xdgRoot ~ "/ccc/config.toml");
    remove(homeRoot ~ "/.config/ccc/config.toml");
}

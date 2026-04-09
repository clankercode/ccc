require "./parser"

def load_config(path : String? = nil) : CccConfig
  config = CccConfig.new

  search_paths = [] of String
  if p = path
    search_paths << p
  else
    if xdg = ENV["XDG_CONFIG_HOME"]?
      search_paths << File.join(xdg, "ccc", "config.toml") unless xdg.empty?
    end
    search_paths << File.join(Path.home, ".config", "ccc", "config.toml")
  end

  config_path : String? = nil
  search_paths.each do |candidate|
    if File.exists?(candidate)
      config_path = candidate
      break
    end
  end

  return config unless config_path

  current_section = ""
  current_alias_name = ""
  current_alias = AliasDef.new

  File.each_line(config_path) do |raw_line|
    line = raw_line.strip
    next if line.empty? || line.starts_with?('#')

    if line == "[defaults]"
      current_section = "defaults"
      next
    elsif line == "[abbreviations]"
      current_section = "abbreviations"
      next
    elsif m = /^\[aliases\.([A-Za-z0-9_-]+)\]$/.match(line)
      current_section = "alias"
      if !current_alias_name.empty?
        config.aliases[current_alias_name] = current_alias
      end
      current_alias_name = m[1]
      current_alias = AliasDef.new
      next
    elsif line.starts_with?("[")
      current_section = ""
      next
    end

    kv = line.split("=", 2)
    next unless kv.size == 2
    key = kv[0].strip
    val = kv[1].strip.gsub(/^"|"$/, "")

    case current_section
    when "defaults"
      case key
      when "runner"      then config.default_runner = val
      when "provider"    then config.default_provider = val
      when "model"       then config.default_model = val
      when "thinking"    then config.default_thinking = val.to_i32?
      end
    when "abbreviations"
      config.abbreviations[key] = val
    when "alias"
      case key
      when "runner"   then current_alias.runner = val.empty? ? nil : val
      when "thinking" then current_alias.thinking = val.to_i32?
      when "provider" then current_alias.provider = val.empty? ? nil : val
      when "model"    then current_alias.model = val.empty? ? nil : val
      when "agent"    then current_alias.agent = val.empty? ? nil : val
      end
    when ""
      case key
      when "default_runner"   then config.default_runner = val
      when "default_provider" then config.default_provider = val
      when "default_model"    then config.default_model = val
      when "default_thinking" then config.default_thinking = val.to_i32?
      end
    end
  end

  if !current_alias_name.empty?
    config.aliases[current_alias_name] = current_alias
  end

  config
end

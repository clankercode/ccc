# frozen_string_literal: true

require_relative "parser"

module CallCodingClis
  module Config
    CONFIG_DIR_NAME = "ccc"
    CONFIG_FILE_NAME = "config.toml"

    def self.load_config(path = nil)
      if path
        return load_from_file(path)
      end

      candidates = []
      xdg = ENV["XDG_CONFIG_HOME"]
      if xdg && !xdg.empty?
        candidates << File.join(xdg, CONFIG_DIR_NAME, CONFIG_FILE_NAME)
      end
      candidates << File.join(Dir.home, ".config", CONFIG_DIR_NAME, CONFIG_FILE_NAME)

      candidates.each do |candidate|
        return load_from_file(candidate) if File.exist?(candidate)
      end

      Parser::CccConfig.new
    end

    def self.load_from_file(path)
      begin
        data = parse_toml(File.read(path, encoding: "utf-8"))
      rescue StandardError
        return Parser::CccConfig.new
      end

      config = Parser::CccConfig.new

      defaults = data["defaults"]
      if defaults.is_a?(Hash)
        config.default_runner = defaults.fetch("runner", config.default_runner)
        config.default_provider = defaults.fetch("provider", config.default_provider)
        config.default_model = defaults.fetch("model", config.default_model)
        if defaults.key?("thinking") && !defaults["thinking"].nil?
          config.default_thinking = defaults["thinking"].to_i
        end
      end

      abbreviations = data["abbreviations"]
      if abbreviations.is_a?(Hash)
        config.abbreviations = abbreviations.transform_keys(&:to_s)
      end

      aliases = data["aliases"]
      if aliases.is_a?(Hash)
        aliases.each do |name, defn|
          next unless defn.is_a?(Hash)
          alias_def = Parser::AliasDef.new(
            runner: defn["runner"],
            thinking: defn.key?("thinking") && !defn["thinking"].nil? ? defn["thinking"].to_i : nil,
            provider: defn["provider"],
            model: defn["model"],
            agent: defn["agent"]
          )
          config.aliases[name.to_s] = alias_def
        end
      end

      config
    end

    def self.parse_toml(content)
      result = {}
      current_section = nil

      content.each_line do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("#")

        if (m = stripped.match(/\A\[(.+)\]\z/))
          parts = m[1].split(".")
          current_section = result
          parts.each do |part|
            current_section[part] ||= {}
            current_section = current_section[part]
          end
        elsif current_section && (m = stripped.match(/\A(\w+)\s*=\s*"(.*)"\z/))
          current_section[m[1]] = m[2]
        elsif current_section && (m = stripped.match(/\A(\w+)\s*=\s*(\d+)\z/))
          current_section[m[1]] = m[2].to_i
        elsif (m = stripped.match(/\A(\w+)\s*=\s*"(.*)"\z/))
          result[m[1]] = m[2]
        elsif (m = stripped.match(/\A(\w+)\s*=\s*(\d+)\z/))
          result[m[1]] = m[2].to_i
        end
      end

      result
    end
  end
end

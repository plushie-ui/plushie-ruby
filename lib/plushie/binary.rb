# frozen_string_literal: true

module Plushie
  # Resolves the path to the plushie renderer binary.
  #
  # Resolution order:
  # 1. PLUSHIE_BINARY_PATH environment variable
  # 2. Downloaded binary in _build/plushie/bin/
  # 3. System PATH
  #
  module Binary
    module_function

    def path!
      path = resolve
      raise Error, "plushie binary not found. Run: plushie download" unless path
      raise Error, "plushie binary not executable: #{path}" unless File.executable?(path)
      path
    end

    def path
      resolve
    end

    def resolve
      # 1. Explicit env var
      if (env_path = ENV["PLUSHIE_BINARY_PATH"])
        return env_path if File.exist?(env_path)
        raise Error, "PLUSHIE_BINARY_PATH set but file not found: #{env_path}"
      end

      # 2. Downloaded binary
      downloaded = downloaded_path
      return downloaded if downloaded && File.exist?(downloaded)

      # 3. System PATH
      system_path = which("plushie")
      return system_path if system_path

      nil
    end

    def downloaded_path
      dir = File.join("_build", "plushie", "bin")
      name = "plushie-#{os_name}-#{arch_name}"
      name += ".exe" if Gem.win_platform?
      path = File.join(dir, name)
      File.exist?(path) ? path : nil
    end

    def os_name
      case RbConfig::CONFIG["host_os"]
      when /linux/i then "linux"
      when /darwin/i then "darwin"
      when /mswin|mingw|cygwin/i then "windows"
      else raise Error, "unsupported OS: #{RbConfig::CONFIG["host_os"]}"
      end
    end

    def arch_name
      case RbConfig::CONFIG["host_cpu"]
      when /x86_64|amd64/i then "x86_64"
      when /aarch64|arm64/i then "aarch64"
      else raise Error, "unsupported architecture: #{RbConfig::CONFIG["host_cpu"]}"
      end
    end

    # Download the precompiled binary for the current platform.
    #
    # @param version [String] binary version (default: BINARY_VERSION)
    # @return [String] path to the downloaded binary
    def download!(version: BINARY_VERSION)
      require "net/http"
      require "uri"
      require "fileutils"

      url = release_url(version)
      dir = File.join("_build", "plushie", "bin")
      FileUtils.mkdir_p(dir)
      dest = File.join(dir, binary_name)

      $stderr.puts "Downloading plushie #{version} for #{os_name}-#{arch_name}..."
      uri = URI.parse(url)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        response = http.get(uri.path)

        case response
        when Net::HTTPSuccess
          File.binwrite(dest, response.body)
          File.chmod(0o755, dest) unless Gem.win_platform?
          $stderr.puts "Saved to #{dest} (#{response.body.bytesize} bytes)"
        when Net::HTTPRedirection
          # Follow one redirect
          redirect_uri = URI.parse(response["location"])
          redirect_response = Net::HTTP.get_response(redirect_uri)
          File.binwrite(dest, redirect_response.body)
          File.chmod(0o755, dest) unless Gem.win_platform?
          $stderr.puts "Saved to #{dest} (#{redirect_response.body.bytesize} bytes)"
        else
          raise Error, "download failed: #{response.code} #{response.message}"
        end
      end

      dest
    end

    # @return [String] GitHub release download URL
    def release_url(version)
      "https://github.com/plushie-ui/plushie/releases/download/v#{version}/#{binary_name}"
    end

    # @return [String] platform-specific binary filename
    def binary_name
      name = "plushie-#{os_name}-#{arch_name}"
      name += ".exe" if Gem.win_platform?
      name
    end

    def which(cmd)
      ENV["PATH"]&.split(File::PATH_SEPARATOR)&.each do |dir|
        path = File.join(dir, cmd)
        return path if File.executable?(path)
      end
      nil
    end
  end
end

require "rbconfig"

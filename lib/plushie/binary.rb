# frozen_string_literal: true

require "fileutils"

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
      raise Error, "plushie binary not found. Run: rake plushie:download" unless path
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
    # Verifies the SHA-256 checksum against a .sha256 sidecar file.
    #
    # @param version [String] binary version (default: BINARY_VERSION)
    # @return [String] path to the downloaded binary
    def download!(version: BINARY_VERSION)
      require "net/http"
      require "uri"
      require "fileutils"
      require "digest"

      url = release_url(version)
      checksum_url = "#{url}.sha256"
      dir = File.join("_build", "plushie", "bin")
      FileUtils.mkdir_p(dir)
      dest = File.join(dir, binary_name)

      warn "Downloading plushie #{version} for #{os_name}-#{arch_name}..."

      binary_data = fetch_url(url)
      checksum_data = fetch_url(checksum_url)

      # The .sha256 file contains "hexdigest  filename\n" or just "hexdigest\n"
      expected_sha = checksum_data.strip.split(/\s+/).first

      actual_sha = Digest::SHA256.hexdigest(binary_data)

      unless actual_sha == expected_sha
        raise Error, "checksum mismatch for #{binary_name}: " \
          "expected #{expected_sha}, got #{actual_sha}"
      end

      File.binwrite(dest, binary_data)
      File.chmod(0o755, dest) unless Gem.win_platform?
      warn "Saved to #{dest} (#{binary_data.bytesize} bytes, SHA-256 verified)"

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

    # Fetch a URL, following one redirect if needed.
    # @param url [String]
    # @return [String] response body
    def fetch_url(url)
      uri = URI.parse(url)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        response = http.get(uri.path)

        case response
        when Net::HTTPSuccess
          response.body
        when Net::HTTPRedirection
          redirect_uri = URI.parse(response["location"])
          Net::HTTP.get(redirect_uri)
        else
          raise Error, "download failed for #{url}: #{response.code} #{response.message}"
        end
      end
    end
    private_class_method :fetch_url

    # Download the WASM renderer tarball and extract it.
    #
    # @param version [String] binary version (default: BINARY_VERSION)
    # @param force [Boolean] re-download even if files exist
    # @return [String] path to the WASM directory
    def download_wasm!(version: BINARY_VERSION, force: false)
      require "net/http"
      require "uri"
      require "fileutils"
      require "digest"
      require "rubygems/package"
      require "zlib"
      require "stringio"

      dir = wasm_path
      js_path = File.join(dir, "plushie_wasm.js")
      wasm_file = File.join(dir, "plushie_wasm_bg.wasm")

      if !force && File.exist?(js_path) && File.exist?(wasm_file)
        warn "WASM files already exist in #{dir}. Use force: true to re-download."
        return dir
      end

      archive_name = "plushie-wasm.tar.gz"
      url = "https://github.com/plushie-ui/plushie/releases/download/v#{version}/#{archive_name}"
      checksum_url = "#{url}.sha256"

      warn "Downloading #{archive_name}..."

      archive_data = fetch_url(url)
      checksum_data = fetch_url(checksum_url)

      expected_sha = checksum_data.strip.split(/\s+/).first
      actual_sha = Digest::SHA256.hexdigest(archive_data)

      unless actual_sha == expected_sha
        raise Error, "checksum mismatch for #{archive_name}: " \
          "expected #{expected_sha}, got #{actual_sha}"
      end

      FileUtils.mkdir_p(dir)

      # Extract tar.gz using Ruby built-ins
      io = StringIO.new(archive_data)
      Zlib::GzipReader.wrap(io) do |gz|
        Gem::Package::TarReader.new(gz) do |tar|
          tar.each do |entry|
            next unless entry.file?
            dest = File.join(dir, File.basename(entry.full_name))
            File.binwrite(dest, entry.read)
          end
        end
      end

      warn "Installed WASM files to #{dir} (SHA-256 verified)"
      dir
    end

    # @return [String] path to the WASM output directory
    def wasm_path
      File.join("_build", "plushie", "wasm")
    end
  end
end

require "rbconfig"

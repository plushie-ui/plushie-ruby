# frozen_string_literal: true

require "fileutils"
require "uri"

module Plushie
  # Resolves the path to the plushie renderer binary.
  #
  # Resolution order (explicit config raises if file missing; implicit
  # discovery silently tries the next option):
  #
  # 1. PLUSHIE_BINARY_PATH environment variable (explicit)
  # 2. Plushie.configuration.binary_path (explicit)
  # 3. Custom extension build in _build/plushie/custom/target/ (implicit)
  # 4. Downloaded binary in bin/ (implicit)
  #
  module Binary
    module_function

    RELEASE_BASE_URL = "https://github.com/plushie-ui/plushie-rust/releases/download"
    RELEASE_BASE_URL_ENV = "PLUSHIE_RELEASE_BASE_URL"

    # Resolve and return the binary path, or raise with helpful instructions.
    #
    # @return [String] path to the plushie binary
    # @raise [Plushie::Error] if no binary found
    def path!
      path = resolve
      unless path
        raise Error, <<~MSG.chomp
          plushie binary not found.

          To download a precompiled binary:
            rake plushie:download

          To build from source:
            rake plushie:build

          To use an existing binary:
            export PLUSHIE_BINARY_PATH=/path/to/plushie
        MSG
      end
      raise Error, "plushie binary not executable: #{path}" unless File.executable?(path)
      path
    end

    # Resolve the binary path, or return nil.
    #
    # @return [String, nil]
    def path
      resolve
    end

    # Full resolution chain.
    #
    # @return [String, nil]
    def resolve
      # 1. Explicit env var (raises if set but missing)
      if (env_path = ENV["PLUSHIE_BINARY_PATH"])
        return env_path if File.exist?(env_path)
        raise Error, "PLUSHIE_BINARY_PATH set but file not found: #{env_path}"
      end

      # 2. Explicit config (raises if set but missing)
      if (config_path = Plushie.configuration.binary_path)
        return config_path if File.exist?(config_path)
        raise Error, "Plushie.configuration.binary_path set to #{config_path.inspect} but file not found"
      end

      # 3. Custom extension build
      custom = custom_build_path
      return custom if custom

      # 4. Downloaded binary
      downloaded = downloaded_path
      return downloaded if downloaded

      nil
    end

    # Path to a custom extension build binary.
    # Checks both release and debug profiles.
    #
    # @return [String, nil]
    def custom_build_path
      build_dir = File.join("_build", "plushie", "custom", "target")
      return nil unless File.directory?(build_dir)

      bin_name = Plushie.configuration.build_name
      ext = Gem.win_platform? ? ".exe" : ""

      %w[release debug].each do |profile|
        path = File.join(build_dir, profile, "#{bin_name}#{ext}")
        return path if File.exist?(path)
      end
      nil
    end

    # Path to the downloaded precompiled binary.
    #
    # @return [String, nil]
    def downloaded_path
      dir = "bin"
      name = binary_name
      path = File.join(dir, name)
      File.exist?(path) ? path : nil
    end

    # Map Ruby platform to binary OS name.
    # @api private
    def os_name
      case RbConfig::CONFIG["host_os"]
      when /linux/i then "linux"
      when /darwin/i then "darwin"
      when /mswin|mingw|cygwin/i then "windows"
      else raise Error, "unsupported OS: #{RbConfig::CONFIG["host_os"]}"
      end
    end

    # Map Ruby architecture to binary architecture name.
    # @api private
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
    # @param version [String] plushie-rust version (default: PLUSHIE_RUST_VERSION)
    # @param dest [String, nil] override destination path (default: bin/{name})
    # @return [String] path to the downloaded binary
    def download!(version: PLUSHIE_RUST_VERSION, dest: nil)
      require "net/http"
      require "uri"
      require "fileutils"
      require "digest"

      url = release_url(version)
      checksum_url = "#{url}.sha256"
      if dest
        FileUtils.mkdir_p(File.dirname(dest))
      else
        dir = "bin"
        FileUtils.mkdir_p(dir)
        dest = File.join(dir, binary_name)
      end

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

    # Download the standalone plushie tool for the current platform.
    #
    # @param version [String] plushie-rust version
    # @param force [Boolean] replace an existing tool
    # @return [String] path to the downloaded tool
    def download_tool!(version: PLUSHIE_RUST_VERSION, force: false)
      require "net/http"
      require "uri"
      require "fileutils"
      require "digest"

      dir = "bin"
      dest = File.join(dir, tool_name)
      return dest if File.exist?(dest) && !force

      FileUtils.mkdir_p(dir)
      url = tool_release_url(version)
      checksum_url = "#{url}.sha256"

      warn "Downloading plushie tool #{version} for #{os_name}-#{arch_name}..."

      binary_data = fetch_url(url)
      checksum_data = fetch_url(checksum_url)
      expected_sha = checksum_data.strip.split(/\s+/).first
      actual_sha = Digest::SHA256.hexdigest(binary_data)

      unless actual_sha == expected_sha
        raise Error, "checksum mismatch for #{tool_name}: " \
          "expected #{expected_sha}, got #{actual_sha}"
      end

      File.binwrite(dest, binary_data)
      File.chmod(0o755, dest) unless Gem.win_platform?
      warn "Saved to #{dest} (#{binary_data.bytesize} bytes, SHA-256 verified)"

      dest
    end

    # Sync the project-local renderer through the standalone plushie tool.
    #
    # @param version [String] plushie-rust version
    # @param force [Boolean] forward --force to the tool
    # @return [String] path to the synced renderer
    def sync_renderer_with_tool!(version: PLUSHIE_RUST_VERSION, force: false)
      args =
        if (source = ENV["PLUSHIE_RUST_SOURCE_PATH"] || Plushie.configuration.source_path) && !source.empty?
          manifest = File.join(source, "Cargo.toml")
          raise Error, "PLUSHIE_RUST_SOURCE_PATH does not contain Cargo.toml: #{source}" unless File.exist?(manifest)

          [
            "cargo",
            "run",
            "--manifest-path",
            manifest,
            "-p",
            "cargo-plushie",
            "--bin",
            "plushie",
            "--release",
            "--quiet",
            "--",
            "tools",
            "sync",
            "--required-version",
            version
          ]
        else
          tool = download_tool!(version: version, force: force)
          [tool, "tools", "sync", "--required-version", version]
        end
      args << "--force" if force
      ok = system(*args)
      raise Error, "bin/plushie download failed" unless ok

      File.join("bin", binary_name)
    end

    # @return [String] GitHub release download URL
    def release_url(version)
      "#{release_base_url}/v#{version}/#{release_name}"
    end

    # @return [String] GitHub release download URL for the plushie tool
    def tool_release_url(version)
      "#{release_base_url}/v#{version}/#{tool_release_name}"
    end

    # @return [String] configured release download base URL
    def release_base_url
      base_url = (ENV[RELEASE_BASE_URL_ENV] || RELEASE_BASE_URL).strip.sub(%r{/+\z}, "")
      raise Error, "#{RELEASE_BASE_URL_ENV} must not be empty" if base_url.empty?

      uri = URI.parse(base_url)
      return base_url if uri.scheme == "https" || uri.scheme == "file"
      return base_url if uri.scheme == "http" && ["localhost", "127.0.0.1", "::1"].include?(uri.host)

      raise Error, "#{RELEASE_BASE_URL_ENV} must use https://, file://, or loopback http://"
    end

    # @return [String] stable project-local binary filename
    def binary_name
      Gem.win_platform? ? "plushie-renderer.exe" : "plushie-renderer"
    end

    # @return [String] platform-specific release artifact filename
    def release_name
      name = "plushie-renderer-#{os_name}-#{arch_name}"
      name += ".exe" if Gem.win_platform?
      name
    end

    # @return [String] stable project-local plushie tool filename
    def tool_name
      Gem.win_platform? ? "plushie.exe" : "plushie"
    end

    # @return [String] platform-specific plushie tool release artifact filename
    def tool_release_name
      name = "plushie-#{os_name}-#{arch_name}"
      name += ".exe" if Gem.win_platform?
      name
    end

    # Fetch a URL, following one redirect if needed.
    # @param url [String]
    # @return [String] response body
    def fetch_url(url, redirect_limit: 10)
      raise Error, "too many redirects for #{url}" if redirect_limit.zero?

      uri = URI.parse(url)

      if uri.scheme == "file"
        return File.binread(uri.path)
      end

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        response = http.get(uri.request_uri)

        case response
        when Net::HTTPSuccess
          response.body
        when Net::HTTPRedirection
          fetch_url(response["location"], redirect_limit: redirect_limit - 1)
        else
          raise Error, "download failed for #{url}: #{response.code} #{response.message}"
        end
      end
    end
    private_class_method :fetch_url

    # Download the WASM renderer tarball and extract it.
    #
    # @param version [String] plushie-rust version (default: PLUSHIE_RUST_VERSION)
    # @param force [Boolean] re-download even if files exist
    # @param dir [String, nil] override output directory (default: wasm_path)
    # @return [String] path to the WASM directory
    def download_wasm!(version: PLUSHIE_RUST_VERSION, force: false, dir: nil)
      require "net/http"
      require "uri"
      require "fileutils"
      require "digest"
      require "rubygems/package"
      require "zlib"
      require "stringio"

      dir ||= wasm_path
      js_path = File.join(dir, "plushie_renderer_wasm.js")
      wasm_file = File.join(dir, "plushie_renderer_wasm_bg.wasm")

      if !force && File.exist?(js_path) && File.exist?(wasm_file)
        warn "WASM files already exist in #{dir}. Use force: true to re-download."
        return dir
      end

      archive_name = "plushie-renderer-wasm.tar.gz"
      url = "#{release_base_url}/v#{version}/#{archive_name}"
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
      File.join("_build", "plushie-renderer", "wasm")
    end
  end
end

require "rbconfig"

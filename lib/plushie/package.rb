# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"

require_relative "../plushie"

module Plushie
  # Standalone package payload and manifest helpers.
  module Package
    DEFAULT_ICON_PATH = "assets/plushie-checkbox-512x512.png"
    DEFAULT_FORWARD_ENV = [
      "PATH",
      "HOME",
      "LANG",
      "LC_ALL",
      "XDG_RUNTIME_DIR",
      "WAYLAND_DISPLAY",
      "DISPLAY"
    ].freeze
    SOURCE_CONFIG = "plushie-package.config.toml"
    SOURCE_CONFIG_VERSION = 1
    RESERVED_FORWARD_ENV = [
      "PLUSHIE_BINARY_PATH",
      "PLUSHIE_PACKAGE_DIR",
      "PLUSHIE_PACKAGE_READY_FILE"
    ].freeze

    PackageStartConfig = Data.define(:working_dir, :command, :forward_env)
    PackageSourceConfig = Data.define(:start)

    module_function

    def build(
      app_id:,
      app_version: "0.1.0",
      app_name: nil,
      project_dir: Dir.pwd,
      output_dir: "dist",
      target: nil,
      renderer_path: nil,
      renderer_kind: "stock",
      renderer_source: nil,
      icon_path: nil,
      entrypoint: "bin/connect",
      package_config: nil,
      sdk_source_path: ENV["PLUSHIE_RUBY_DIR"],
      bundle_without: "development test",
      ruby_provider: "local",
      ruby_root: nil,
      ruby_version: nil
    )
      require_command("bundle")
      require_command("ruby")
      require_command("tar")

      project_dir = File.expand_path(project_dir)
      output_dir = File.expand_path(output_dir, project_dir)
      payload_dir = File.join(output_dir, "payload")
      app_dir = File.join(payload_dir, "app")
      ruby_dir = File.join(payload_dir, "ruby")
      archive_path = File.join(output_dir, "payload.tar.zst")

      renderer = resolve_renderer!(
        path: renderer_path,
        kind: renderer_kind,
        source: renderer_source
      )
      start_config = resolve_start_config(project_dir, package_config, entrypoint)

      FileUtils.rm_rf(output_dir)
      FileUtils.mkdir_p(File.join(app_dir, "bin"))
      FileUtils.mkdir_p(File.join(app_dir, "lib"))
      FileUtils.mkdir_p(File.join(app_dir, ".bundle"))
      FileUtils.mkdir_p(File.join(payload_dir, "bin"))
      FileUtils.mkdir_p(ruby_dir)

      copy_ruby_runtime!(
        ruby_dir,
        provider: ruby_provider,
        root: ruby_root,
        version: ruby_version
      )
      copy_app!(project_dir, payload_dir, app_dir, start_config, entrypoint, sdk_source_path)
      install_runtime_gems!(app_dir, bundle_without)
      install_renderer!(renderer.fetch(:source_path), File.join(payload_dir, renderer.fetch(:payload_path)))
      package_icon_path = install_package_icons!(payload_dir, project_dir, icon_path)
      dereference_payload_symlinks!(payload_dir)

      archive_payload!(payload_dir, archive_path)

      manifest = manifest_for_payload(
        app_id: app_id,
        app_name: app_name,
        app_version: app_version,
        target: target,
        renderer_kind: renderer.fetch(:kind),
        renderer_source: renderer.fetch(:source),
        renderer_path: renderer.fetch(:payload_path),
        icon_path: package_icon_path,
        start_command: start_config.command,
        working_dir: start_config.working_dir,
        forward_env: start_config.forward_env,
        payload_archive: archive_path
      )

      manifest_path = File.join(output_dir, "plushie-package.toml")
      write_manifest(manifest_path, manifest)

      {
        output_dir: output_dir,
        payload_dir: payload_dir,
        archive_path: archive_path,
        manifest_path: manifest_path,
        payload_hash: manifest.fetch(:payload_hash),
        payload_size: manifest.fetch(:payload_size)
      }
    end

    def normalize_package_target(os_name, arch)
      os_key = os_name.to_s.downcase
      os_part = case os_key
      when /\Alinux/ then "linux"
      when /\Adarwin/, "macos" then "darwin"
      when "win32", "windows", "cygwin", /\Amsys/, /\Amingw/ then "windows"
      else raise Error, "unsupported package OS: #{os_name}"
      end

      arch_key = arch.to_s.downcase
      arch_part = case arch_key
      when "amd64", "x64", "x86_64" then "x86_64"
      when "arm64", "aarch64" then "aarch64"
      else raise Error, "unsupported package architecture: #{arch}"
      end

      "#{os_part}-#{arch_part}"
    end

    def package_target
      normalize_package_target(RbConfig::CONFIG.fetch("host_os"), RbConfig::CONFIG.fetch("host_cpu"))
    end

    def sha256_file(path)
      digest = Digest::SHA256.new
      File.open(path, "rb") do |file|
        while (chunk = file.read(1024 * 1024))
          digest.update(chunk)
        end
      end
      digest.hexdigest
    end

    def file_size(path)
      File.size(path)
    end

    def manifest_for_payload(
      app_id:,
      app_version:,
      renderer_path:,
      start_command:,
      payload_archive:,
      app_name: nil,
      target: nil,
      renderer_kind: "stock",
      renderer_source: "local-resolve",
      icon_path: DEFAULT_ICON_PATH,
      working_dir: ".",
      forward_env: DEFAULT_FORWARD_ENV
    )
      archive_path = File.expand_path(payload_archive)
      {
        app_id: app_id,
        app_name: app_name,
        app_version: app_version,
        target: target || package_target,
        renderer: {
          kind: renderer_kind,
          source: renderer_source,
          path: renderer_path
        },
        platform: {
          icon: icon_path
        },
        start_command: start_command,
        working_dir: working_dir,
        forward_env: forward_env,
        payload_archive: File.basename(archive_path),
        payload_hash: sha256_file(archive_path),
        payload_size: file_size(archive_path)
      }
    end

    def render_manifest(manifest)
      lines = [
        "schema_version = 1",
        "app_id = #{toml_string(manifest.fetch(:app_id))}"
      ]
      app_name = manifest[:app_name]
      lines << "app_name = #{toml_string(app_name)}" if app_name
      lines.concat([
        "app_version = #{toml_string(manifest.fetch(:app_version))}",
        "target = #{toml_string(manifest.fetch(:target))}",
        "host_sdk = \"ruby\"",
        "host_sdk_version = #{toml_string(Plushie::VERSION)}",
        "plushie_rust_version = #{toml_string(Plushie::PLUSHIE_RUST_VERSION)}",
        "protocol_version = #{Plushie::Protocol::PROTOCOL_VERSION}",
        "",
        "[start]",
        "working_dir = #{toml_string(manifest.fetch(:working_dir))}",
        "command = #{toml_array(manifest.fetch(:start_command))}",
        "forward_env = #{toml_array(manifest.fetch(:forward_env))}",
        "",
        "[platform]",
        "icon = #{toml_string(manifest.fetch(:platform).fetch(:icon))}",
        "",
        "[renderer]",
        "path = #{toml_string(manifest.fetch(:renderer).fetch(:path))}",
        "kind = #{toml_string(manifest.fetch(:renderer).fetch(:kind))}",
        "source = #{toml_string(manifest.fetch(:renderer).fetch(:source))}",
        "",
        "[payload]",
        "archive = #{toml_string(manifest.fetch(:payload_archive))}",
        "hash = #{toml_string("sha256:#{manifest.fetch(:payload_hash)}")}",
        "size = #{manifest.fetch(:payload_size)}",
        ""
      ])
      lines.join("\n")
    end

    def write_manifest(path, manifest)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, render_manifest(manifest))
    end

    def default_source_config_path(project_dir)
      File.join(project_dir, SOURCE_CONFIG)
    end

    def default_source_config(entrypoint = "bin/connect")
      PackageSourceConfig.new(
        start: PackageStartConfig.new(
          working_dir: "app",
          command: start_command(entrypoint),
          forward_env: DEFAULT_FORWARD_ENV
        )
      )
    end

    def render_source_config(config = default_source_config)
      validate_source_config!(config)
      lines = [
        "# Plushie standalone package config.",
        "# Commit this file and edit it when the packaged app needs a",
        "# different entry point, working directory, or forwarded environment.",
        "",
        "config_version = 1",
        "",
        "[start]",
        "# Relative to the extracted app package.",
        "working_dir = #{toml_string(config.start.working_dir)}",
        "# Structured argv. The first item is the packaged host executable.",
        "command = #{toml_array(config.start.command)}",
        "# Environment variable names copied from the parent process.",
        "forward_env = ["
      ]
      lines.concat(config.start.forward_env.map { |name| "  #{toml_string(name)}," })
      lines.concat(["]", ""])
      lines.join("\n")
    end

    def write_source_config(path, config = default_source_config)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, render_source_config(config))
    end

    def load_source_config(path)
      parse_source_config(File.read(path))
    rescue SystemCallError => e
      raise Error, "failed to read package config #{path}: #{e.message}"
    end

    def load_default_source_config(project_dir)
      path = default_source_config_path(project_dir)
      return nil unless File.file?(path)

      load_source_config(path)
    end

    def parse_source_config(text)
      document = parse_source_config_document(text)
      version = document.fetch(:config_version) do
        raise Error, "package config missing config_version"
      end
      unless version == SOURCE_CONFIG_VERSION
        raise Error, "unsupported package config config_version #{version}"
      end

      start = document.fetch(:start) do
        raise Error, "package config missing [start]"
      end
      config = PackageSourceConfig.new(
        start: PackageStartConfig.new(
          working_dir: start.fetch(:working_dir),
          command: start.fetch(:command),
          forward_env: start.fetch(:forward_env)
        )
      )
      validate_source_config!(config)
      config
    rescue KeyError => e
      raise Error, "package config missing #{e.key}"
    end

    def validate_source_config!(config)
      validate_start_config!(config.start)
      config
    end

    def validate_start_config!(start)
      validate_payload_relative_path!("start.working_dir", start.working_dir, allow_dot: true)
      unless start.command.is_a?(Array) && !start.command.empty? && start.command.all? { |arg| arg.is_a?(String) && !arg.empty? }
        raise Error, "start.command must contain a non-empty argv"
      end
      validate_payload_relative_path!("start.command[0]", start.command.fetch(0), allow_dot: false)
      unless start.forward_env.is_a?(Array) && start.forward_env.all? { |name| valid_forward_env_name?(name) }
        raise Error, "start.forward_env must contain only non-empty variable names without comma or equals"
      end
      if start.forward_env.any? { |name| RESERVED_FORWARD_ENV.include?(name) }
        raise Error, "start.forward_env must not include launcher-owned package variables"
      end
      start
    end

    def archive_payload!(payload_dir, archive_path)
      validate_payload_archive_inputs!(payload_dir)
      FileUtils.mkdir_p(File.dirname(archive_path))

      tar = archive_tar!
      args = [
        "-C", payload_dir,
        "--sort=name",
        "--mtime=UTC 1970-01-01",
        "--owner=0",
        "--group=0",
        "--numeric-owner"
      ]

      if tar_supports_zstd?(tar)
        run!([tar, *args, "--zstd", "-cf", archive_path, "."])
      elsif command_available?("zstd")
        statuses = Open3.pipeline([tar, *args, "-cf", "-", "."], ["zstd", "-q", "-o", archive_path])
        raise Error, "payload archive pipeline failed" unless statuses.all?(&:success?)
      else
        raise Error, "missing required command: zstd"
      end
    end

    def validate_payload_archive_inputs!(payload_dir)
      Find.find(payload_dir) do |path|
        next if path == payload_dir

        stat = File.lstat(path)
        if stat.symlink?
          raise Error, "payload contains unsupported symlink: #{relative_payload_path(payload_dir, path)}"
        elsif stat.chardev? || stat.blockdev? || stat.socket? || stat.pipe?
          raise Error, "payload contains unsupported special file: #{relative_payload_path(payload_dir, path)}"
        elsif stat.file? && stat.nlink > 1
          raise Error, "payload contains unsupported hard-linked file: #{relative_payload_path(payload_dir, path)}"
        end
      end
    end

    def resolve_renderer!(path: nil, kind: "stock", source: nil)
      source_path = nil
      resolved_source = source

      if path && !path.empty?
        source_path = path
        resolved_source ||= "local-path"
        ensure_package_tools_available!
      elsif ENV["PLUSHIE_BINARY_PATH"] && !ENV["PLUSHIE_BINARY_PATH"].empty?
        source_path = ENV["PLUSHIE_BINARY_PATH"]
        resolved_source ||= "local-path"
        ensure_package_tools_available!
      elsif kind != "stock"
        raise Error, "Custom renderer packages require --renderer-path or PLUSHIE_BINARY_PATH"
      elsif source_path_configured?
        source_path = Binary.sync_renderer_with_tool!
        resolved_source ||= "local-build"
      else
        source_path = Binary.sync_renderer_with_tool!
        resolved_source ||= "download"
      end

      unless source_path
        raise Error, "No renderer binary found. Run bundle exec rake plushie:download or set PLUSHIE_BINARY_PATH."
      end

      validate_renderer!(source_path)

      {
        kind: kind,
        source: resolved_source || "local-resolve",
        source_path: source_path,
        payload_path: renderer_payload_path
      }
    end

    def ensure_package_tools_available!
      missing = [
        File.join("bin", Binary.tool_name),
        File.join("bin", Binary.launcher_name)
      ].reject { |candidate| File.file?(candidate) }

      return if missing.empty?

      raise Error, "Portable packaging requires the managed Plushie tool set. " \
                   "Missing: #{missing.join(", ")}. Run bundle exec rake plushie:download."
    end

    def source_path_configured?
      source_path = ENV["PLUSHIE_RUST_SOURCE_PATH"] || Plushie.configuration.source_path
      source_path && !source_path.empty?
    end

    def run_cli(argv)
      options = {
        project_dir: Dir.pwd,
        output_dir: "dist",
        renderer_kind: "stock",
        renderer_source: nil,
        entrypoint: "bin/connect",
        package_config: nil,
        write_package_config: false,
        portable: false,
        portable_out: nil,
        strict_tools: false,
        bundle_without: "development test"
      }
      show_help = false

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: ruby -rplushie/package -e 'Plushie::Package.run_cli(ARGV)' -- [options]"
        opts.on("--app-id ID", "Package app identifier") { |value| options[:app_id] = value }
        opts.on("--app-name NAME", "Display app name") { |value| options[:app_name] = value }
        opts.on("--app-version VERSION", "Package app version") { |value| options[:app_version] = value }
        opts.on("--project-dir DIR", "Application project directory") { |value| options[:project_dir] = value }
        opts.on("--output DIR", "Output directory") { |value| options[:output_dir] = value }
        opts.on("--target TARGET", "Package target") { |value| options[:target] = value }
        opts.on("--renderer-path PATH", "Renderer binary to copy") { |value| options[:renderer_path] = value }
        opts.on("--renderer-kind KIND", "Renderer kind") { |value| options[:renderer_kind] = value }
        opts.on("--renderer-source SOURCE", "Renderer provenance source") { |value| options[:renderer_source] = value }
        opts.on("--icon PATH", "App icon to copy into the payload") { |value| options[:icon_path] = value }
        opts.on("--entrypoint PATH", "Payload app entrypoint") { |value| options[:entrypoint] = value }
        opts.on("--package-config PATH", "Developer-owned package config") { |value| options[:package_config] = value }
        opts.on("--write-package-config", "Write a package config template and exit") { options[:write_package_config] = true }
        opts.on("--portable", "Build the portable launcher after writing the manifest") { options[:portable] = true }
        opts.on("--portable-out PATH", "Output path for the portable launcher") { |value| options[:portable_out] = value }
        opts.on("--strict-tools", "Require native packaging tools during portable packaging") { options[:strict_tools] = true }
        opts.on("--sdk-source-path DIR", "Local plushie Ruby SDK source to vendor") { |value| options[:sdk_source_path] = value }
        opts.on("--bundle-without GROUPS", "Bundler groups to exclude") { |value| options[:bundle_without] = value }
        opts.on("--ruby-provider PROVIDER", "Ruby runtime provider: local, path, or mise") { |value| options[:ruby_provider] = value }
        opts.on("--ruby-root DIR", "Ruby runtime root for path provider") { |value| options[:ruby_root] = value }
        opts.on("--ruby-version VERSION", "Ruby version for mise provider") { |value| options[:ruby_version] = value }
        opts.on("-h", "--help", "Show help") { show_help = true }
      end

      parser.parse!(argv)
      if show_help
        puts parser
        return
      end

      if options[:write_package_config]
        path = File.expand_path(options[:package_config] || SOURCE_CONFIG, options[:project_dir])
        write_source_config(path, default_source_config(options[:entrypoint]))
        puts "Wrote #{path}"
        return
      end

      raise Error, "--app-id is required" unless options[:app_id]

      build_options = options.except(:portable, :portable_out, :strict_tools)
      result = build(**build_options)
      puts "Wrote #{result.fetch(:archive_path)}"
      puts "Wrote #{result.fetch(:manifest_path)}"
      verify_strict_package_tools! if options[:strict_tools]
      portable_command = portable_package_command(
        result.fetch(:manifest_path),
        options[:portable_out],
        options[:strict_tools]
      )
      if options[:portable]
        run!(portable_command)
      else
        puts "Build launcher with:"
        puts "  #{portable_command.join(" ")}"
      end
    end

    def portable_package_command(manifest_path, portable_out = nil, strict_tools = false)
      command = [File.join("bin", Binary.tool_name), "package", "portable", "--manifest", manifest_path]
      command += ["--out", portable_out] if portable_out
      command += ["--strict-tools"] if strict_tools
      command
    end

    def verify_strict_package_tools!
      run!([
        File.join("bin", Binary.tool_name),
        "tools",
        "check",
        "--required-version",
        PLUSHIE_RUST_VERSION
      ])
    end

    def env_value(name, default = nil)
      value = ENV[name]
      (value.nil? || value.empty?) ? default : value
    end

    def env_flag(name, default = false)
      value = ENV[name]
      return default if value.nil? || value.empty?

      case value.downcase
      when "1", "true", "yes", "on" then true
      when "0", "false", "no", "off" then false
      else raise Error, "#{name} must be true or false"
      end
    end

    def build_from_env(overrides = {})
      app_id = package_option(overrides, :app_id, "PLUSHIE_PACKAGE_APP_ID")
      raise Error, "PLUSHIE_PACKAGE_APP_ID is required" unless app_id

      build(
        app_id: app_id,
        app_name: package_option(overrides, :app_name, "PLUSHIE_PACKAGE_APP_NAME"),
        app_version: package_option(overrides, :app_version, "PLUSHIE_PACKAGE_APP_VERSION", "0.1.0"),
        project_dir: package_option(overrides, :project_dir, "PLUSHIE_PACKAGE_PROJECT_DIR", Dir.pwd),
        output_dir: package_option(overrides, :output_dir, "PLUSHIE_PACKAGE_OUTPUT", "dist"),
        target: package_option(overrides, :target, "PLUSHIE_PACKAGE_TARGET"),
        renderer_path: package_option(overrides, :renderer_path, "PLUSHIE_PACKAGE_RENDERER_PATH"),
        renderer_kind: package_option(overrides, :renderer_kind, "PLUSHIE_PACKAGE_RENDERER_KIND", "stock"),
        renderer_source: package_option(overrides, :renderer_source, "PLUSHIE_PACKAGE_RENDERER_SOURCE"),
        icon_path: package_option(overrides, :icon_path, "PLUSHIE_PACKAGE_ICON_PATH"),
        entrypoint: package_option(overrides, :entrypoint, "PLUSHIE_PACKAGE_ENTRYPOINT", "bin/connect"),
        package_config: package_option(overrides, :package_config, "PLUSHIE_PACKAGE_CONFIG"),
        sdk_source_path: package_option(overrides, :sdk_source_path, "PLUSHIE_RUBY_DIR"),
        bundle_without: package_option(overrides, :bundle_without, "PLUSHIE_PACKAGE_BUNDLE_WITHOUT", "development test"),
        ruby_provider: package_option(overrides, :ruby_provider, "PLUSHIE_RUBY_PROVIDER", "local"),
        ruby_root: package_option(overrides, :ruby_root, "PLUSHIE_RUBY_ROOT"),
        ruby_version: package_option(overrides, :ruby_version, "PLUSHIE_RUBY_VERSION")
      )
    end

    def package_option(overrides, key, env_name, default = nil)
      value = overrides[key]
      (value.nil? || value.empty?) ? env_value(env_name, default) : value
    end

    def resolve_start_config(project_dir, package_config, entrypoint)
      config =
        if package_config && !package_config.empty?
          load_source_config(File.expand_path(package_config, project_dir))
        else
          load_default_source_config(project_dir)
        end
      return config.start if config

      start = PackageStartConfig.new(
        working_dir: "app",
        command: start_command(entrypoint),
        forward_env: DEFAULT_FORWARD_ENV
      )
      validate_start_config!(start)
    end

    def start_command(entrypoint)
      ruby = RbConfig::CONFIG.fetch("ruby_install_name") + RbConfig::CONFIG.fetch("EXEEXT")
      [File.join("ruby", "bin", ruby), entrypoint]
    end

    def renderer_payload_path
      File.join("bin", "plushie-renderer#{RbConfig::CONFIG.fetch("EXEEXT")}")
    end

    def copy_ruby_runtime!(ruby_dir, provider: "local", root: nil, version: nil)
      copy_dir_contents(resolve_ruby_runtime_root(provider: provider, root: root, version: version), ruby_dir)
    end

    def resolve_ruby_runtime_root(provider: "local", root: nil, version: nil)
      case provider
      when "local"
        RbConfig::CONFIG.fetch("prefix")
      when "path"
        raise Error, "--ruby-root is required when --ruby-provider path is used" if root.nil? || root.empty?

        root
      when "mise"
        resolve_mise_runtime("ruby", version)
      else
        raise Error, "unsupported Ruby runtime provider: #{provider}"
      end
    end

    def resolve_mise_runtime(tool, version)
      require_command("mise")
      spec = (version && !version.empty?) ? "#{tool}@#{version}" : tool
      stdout, stderr, status = Open3.capture3("mise", "where", spec)
      raise Error, "mise where #{spec} failed: #{stderr.empty? ? stdout : stderr}" unless status.success?

      root = stdout.strip
      raise Error, "mise where #{spec} returned an empty path" if root.empty?

      root
    end

    def copy_app!(project_dir, payload_dir, app_dir, start_config, entrypoint, sdk_source_path)
      copy_required_path(File.join(project_dir, "lib"), File.join(app_dir, "lib"))
      if start_config.command == start_command(entrypoint)
        copy_entrypoint!(project_dir, app_dir, entrypoint)
      else
        copy_entrypoint!(project_dir, payload_dir, start_config.command.fetch(0))
      end

      if sdk_source_path && !sdk_source_path.empty? && File.directory?(File.join(sdk_source_path, "lib", "plushie"))
        puts "Using local plushie SDK from #{sdk_source_path}"
        vendor_dir = File.join(app_dir, "vendor", "plushie-ruby")
        FileUtils.mkdir_p(vendor_dir)
        copy_dir_contents(sdk_source_path, vendor_dir)
        FileUtils.rm_rf(File.join(vendor_dir, ".git"))
        File.write(File.join(app_dir, "Gemfile"), local_sdk_gemfile)
      else
        copy_required_path(File.join(project_dir, "Gemfile"), File.join(app_dir, "Gemfile"))
      end
    end

    def copy_entrypoint!(project_dir, dest_root, entrypoint)
      copy_required_path(File.join(project_dir, entrypoint), File.join(dest_root, entrypoint))
      FileUtils.chmod(0o755, File.join(dest_root, entrypoint))
    end

    def install_runtime_gems!(app_dir, bundle_without)
      Dir.chdir(app_dir) do
        run_unbundled!(%w[bundle config set --local path vendor/bundle])
        run_unbundled!(["bundle", "config", "set", "--local", "without", bundle_without])
        run_unbundled!(%w[bundle install])
      end
    end

    def install_renderer!(source_path, dest_path)
      FileUtils.mkdir_p(File.dirname(dest_path))
      FileUtils.cp(source_path, dest_path)
      FileUtils.chmod(0o755, dest_path)
    end

    def install_package_icons!(payload_dir, project_dir, icon_path)
      assets_dir = File.join(payload_dir, "assets")
      return DEFAULT_ICON_PATH.tap { materialize_default_icons!(assets_dir) } if icon_path.nil? || icon_path.empty?

      install_app_icon!(project_dir, assets_dir, icon_path)
    end

    def materialize_default_icons!(assets_dir)
      FileUtils.mkdir_p(assets_dir)
      source_path = ENV["PLUSHIE_RUST_SOURCE_PATH"] || Plushie.configuration.source_path
      if source_path && !source_path.empty?
        run!([
          "cargo",
          "run",
          "--manifest-path",
          File.join(source_path, "Cargo.toml"),
          "-p",
          "cargo-plushie",
          "--bin",
          "plushie",
          "--release",
          "--quiet",
          "--",
          "default-icons",
          "--out",
          assets_dir
        ])
      else
        run!([File.join("bin", Binary.tool_name), "default-icons", "--out", assets_dir])
      end
    end

    def install_app_icon!(project_dir, assets_dir, icon_path)
      source = File.expand_path(icon_path, project_dir)
      raise Error, "App icon path is missing: #{source}" unless File.file?(source)

      name = File.basename(source)
      dest = File.join(assets_dir, name)
      FileUtils.mkdir_p(assets_dir)
      FileUtils.cp(source, dest)
      "assets/#{name}"
    end

    def dereference_payload_symlinks!(payload_dir)
      loop do
        links = symlink_paths(payload_dir)
        break if links.empty?

        links.each { |link| dereference_symlink!(link) }
      end
    end

    def renderer_from_source_path
      source_path = ENV["PLUSHIE_RUST_SOURCE_PATH"]
      return nil if source_path.nil? || source_path.empty?

      manifest = File.join(source_path, "Cargo.toml")
      unless File.file?(manifest)
        raise Error, "PLUSHIE_RUST_SOURCE_PATH does not look like a Rust workspace: #{source_path}"
      end

      require_command("cargo")
      puts "Building plushie-renderer from #{source_path}"
      target_dir = File.expand_path(File.join("build", "plushie-package-target"), Dir.pwd)
      Dir.chdir(source_path) do
        run!(["cargo", "build", "--release", "-p", "plushie-renderer", "--target-dir", target_dir])
      end
      File.join(target_dir, "release", "plushie-renderer#{RbConfig::CONFIG.fetch("EXEEXT")}")
    end

    def validate_renderer!(path)
      raise Error, "Renderer binary not found at #{path}" unless File.exist?(path)

      FileUtils.chmod(0o755, path)
      path
    end

    def copy_required_path(source, dest)
      raise Error, "Required package path is missing: #{source}" unless File.exist?(source)

      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.rm_rf(dest)
      FileUtils.cp_r(source, dest, preserve: true)
    end

    def copy_dir_contents(source, dest)
      raise Error, "Required package directory is missing: #{source}" unless File.directory?(source)

      FileUtils.mkdir_p(dest)
      Dir.children(source).each do |entry|
        FileUtils.cp_r(File.join(source, entry), File.join(dest, entry), preserve: true)
      end
    end

    def symlink_paths(payload_dir)
      links = []
      Find.find(payload_dir) do |path|
        links << path if File.lstat(path).symlink?
      end
      links
    end

    def dereference_symlink!(link)
      target = File.readlink(link)
      target = File.expand_path(target, File.dirname(link)) unless target.start_with?(File::SEPARATOR)
      raise Error, "payload symlink target is missing: #{link}" unless File.exist?(target)

      tmp = "#{link}.deref.#{$$}"
      FileUtils.rm_rf(tmp)
      if File.directory?(target)
        FileUtils.mkdir_p(tmp)
        copy_dir_contents(target, tmp)
      else
        FileUtils.cp(target, tmp, preserve: true)
      end
      FileUtils.rm(link)
      FileUtils.mv(tmp, link)
    end

    def archive_tar!
      if gnu_tar?("tar")
        "tar"
      elsif command_available?("gtar") && gnu_tar?("gtar")
        "gtar"
      else
        raise Error, "GNU tar or gtar is required for deterministic payload archives"
      end
    end

    def gnu_tar?(command)
      output, status = Open3.capture2e(command, "--version")
      status.success? && output.include?("GNU tar")
    rescue Errno::ENOENT
      false
    end

    def tar_supports_zstd?(command)
      output, status = Open3.capture2e(command, "--help")
      status.success? && output.include?("--zstd")
    rescue Errno::ENOENT
      false
    end

    def run!(command)
      success = system(*command)
      raise Error, "#{command.first} failed" unless success
    end

    def run_unbundled!(command)
      success =
        if defined?(::Bundler) && ::Bundler.respond_to?(:with_unbundled_env)
          ::Bundler.with_unbundled_env { system(*command) }
        else
          env = ENV.to_h.reject do |key, _value|
            key.start_with?("BUNDLE_") || %w[GEM_HOME GEM_PATH RUBYLIB RUBYOPT].include?(key)
          end
          system(env, *command)
        end
      raise Error, "#{command.first} failed" unless success
    end

    def require_command(command)
      raise Error, "Missing required command: #{command}" unless command_available?(command)
    end

    def command_available?(command)
      !find_executable(command).nil?
    end

    def find_executable(command)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
        path = File.join(dir, command)
        return path if File.executable?(path)
      end
      nil
    end

    def local_sdk_gemfile
      <<~GEMFILE
        # frozen_string_literal: true

        source "https://rubygems.org"

        gem "plushie", path: "vendor/plushie-ruby"
      GEMFILE
    end

    def relative_payload_path(payload_dir, path)
      path.delete_prefix("#{payload_dir}#{File::SEPARATOR}")
    end

    def parse_source_config_document(text)
      document = {start: {}}
      each_toml_assignment(text) do |section, key, value|
        case [section, key]
        when [nil, "config_version"]
          document[:config_version] = parse_toml_integer("config_version", value)
        when ["start", "working_dir"]
          document.fetch(:start)[:working_dir] = parse_toml_string("start.working_dir", value)
        when ["start", "command"]
          document.fetch(:start)[:command] = parse_toml_string_array("start.command", value)
        when ["start", "forward_env"]
          document.fetch(:start)[:forward_env] = parse_toml_string_array("start.forward_env", value)
        else
          name = section ? "#{section}.#{key}" : key
          raise Error, "unsupported package config key #{name}"
        end
      end
      document
    end

    def each_toml_assignment(text)
      section = nil
      pending = nil
      text.each_line.with_index(1) do |line, line_no|
        stripped = strip_toml_comment(line).strip
        next if stripped.empty?

        if pending
          pending[:value] << "\n" << stripped
          if stripped.end_with?("]")
            yield pending.fetch(:section), pending.fetch(:key), pending.fetch(:value)
            pending = nil
          end
          next
        end

        if (match = stripped.match(/\A\[([A-Za-z0-9_]+)\]\z/))
          section = match[1]
          raise Error, "unsupported package config table #{section}" unless section == "start"
          next
        end

        match = stripped.match(/\A([A-Za-z0-9_]+)\s*=\s*(.+)\z/)
        raise Error, "invalid package config line #{line_no}" unless match

        key = match[1]
        value = match[2].strip
        if value.start_with?("[") && !value.end_with?("]")
          pending = {section: section, key: key, value: value}
        else
          yield section, key, value
        end
      end
      raise Error, "unterminated package config array" if pending
    end

    def strip_toml_comment(line)
      in_string = false
      escaped = false
      line.each_char.with_index do |char, index|
        if in_string
          escaped = char == "\\" && !escaped
          if char == "\"" && !escaped
            in_string = false
          elsif char != "\\"
            escaped = false
          end
        elsif char == "\""
          in_string = true
        elsif char == "#"
          return line[0...index]
        end
      end
      line
    end

    def parse_toml_integer(name, value)
      raise Error, "#{name} must be an integer" unless value.match?(/\A\d+\z/)

      value.to_i
    end

    def parse_toml_string(name, value)
      parsed = JSON.parse(value)
      raise Error, "#{name} must be a string" unless parsed.is_a?(String)

      parsed
    rescue JSON::ParserError
      raise Error, "#{name} must be a string"
    end

    def parse_toml_string_array(name, value)
      parsed = JSON.parse(value.gsub(/,\s*\]/, "]"))
      unless parsed.is_a?(Array) && parsed.all? { |item| item.is_a?(String) }
        raise Error, "#{name} must be an array of strings"
      end

      parsed
    rescue JSON::ParserError
      raise Error, "#{name} must be an array of strings"
    end

    def validate_payload_relative_path!(name, value, allow_dot:)
      raise Error, "#{name} must not be empty" unless value.is_a?(String) && !value.strip.empty?
      path = Pathname.new(value)
      if path.absolute? || value.start_with?("\\") || value.match?(/\A[A-Za-z]:[\\\/]/)
        raise Error, "#{name} must be payload-relative, got absolute path #{value}"
      end

      has_normal_component = false
      value.split(/[\\\/]+/).each do |part|
        next if part.empty?

        if part == ".."
          raise Error, "#{name} must not contain parent traversal: #{value}"
        elsif part != "."
          has_normal_component = true
        end
      end
      raise Error, "#{name} must name a payload file path" unless has_normal_component || allow_dot
    end

    def valid_forward_env_name?(name)
      name.is_a?(String) && !name.strip.empty? && !name.include?(",") && !name.include?("=")
    end

    def toml_string(value)
      JSON.generate(value.to_s)
    end

    def toml_array(values)
      "[" + values.map { |value| toml_string(value) }.join(", ") + "]"
    end
  end
end

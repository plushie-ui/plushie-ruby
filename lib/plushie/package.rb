# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"

require_relative "../plushie"
require_relative "widget/native_build"

module Plushie
  # Standalone package payload and manifest helpers.
  module Package
    SOURCE_CONFIG = "plushie-package.config.toml"
    RESERVED_FORWARD_ENV = [
      "PLUSHIE_BINARY_PATH",
      "PLUSHIE_PACKAGE_DIR",
      "PLUSHIE_PACKAGE_READY_FILE"
    ].freeze

    PackageStartConfig = Data.define(:command)

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

      project_dir = File.expand_path(project_dir)
      output_dir = File.expand_path(output_dir, project_dir)
      payload_dir = File.join(output_dir, "payload")
      ruby_dir = File.join(payload_dir, "ruby")

      renderer = resolve_renderer!(
        path: renderer_path,
        kind: renderer_kind
      )
      resolved_target = target || package_target
      start_command = start_command(entrypoint, resolved_target)

      FileUtils.rm_rf(output_dir)
      FileUtils.mkdir_p(File.join(payload_dir, "bin"))
      FileUtils.mkdir_p(File.join(payload_dir, "lib"))
      FileUtils.mkdir_p(File.join(payload_dir, ".bundle"))
      FileUtils.mkdir_p(ruby_dir)

      copy_ruby_runtime!(
        ruby_dir,
        provider: ruby_provider,
        root: ruby_root,
        version: ruby_version
      )
      copy_app!(project_dir, payload_dir, entrypoint, sdk_source_path, resolved_target)
      install_runtime_gems!(payload_dir, bundle_without)
      install_renderer!(renderer.fetch(:source_path), File.join(payload_dir, renderer.fetch(:payload_path)))

      manifest_path = File.join(output_dir, "plushie-package.toml")
      write_partial_manifest(
        manifest_path,
        app_id: app_id,
        app_name: app_name,
        app_version: app_version,
        target: resolved_target,
        renderer_kind: renderer.fetch(:kind),
        renderer_path: renderer.fetch(:payload_path),
        start_command: start_command
      )

      assemble_args = [
        File.join("bin", Binary.tool_name),
        "package", "assemble",
        "--manifest", manifest_path,
        "--payload-dir", payload_dir
      ]
      assemble_args.concat(["--package-config", File.expand_path(package_config, project_dir)]) if package_config && !package_config.empty?
      run!(assemble_args)

      {
        output_dir: output_dir,
        payload_dir: payload_dir,
        manifest_path: manifest_path
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

    def write_partial_manifest(path, app_id:, app_version:, renderer_path:, start_command:, app_name: nil, target: nil, renderer_kind: "stock")
      lines = [
        "schema_version = 1",
        "app_id = #{toml_string(app_id)}"
      ]
      lines << "app_name = #{toml_string(app_name)}" if app_name
      lines.concat([
        "app_version = #{toml_string(app_version)}",
        "target = #{toml_string(target || package_target)}",
        "host_sdk = \"ruby\"",
        "host_sdk_version = #{toml_string(Plushie::VERSION)}",
        "plushie_rust_version = #{toml_string(Plushie::PLUSHIE_RUST_VERSION)}",
        "protocol_version = #{Plushie::Protocol::PROTOCOL_VERSION}",
        "",
        "[start]",
        "command = #{toml_array(start_command)}",
        "",
        "[renderer]",
        "path = #{toml_string(renderer_path)}",
        "kind = #{toml_string(renderer_kind)}",
        ""
      ])
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, lines.join("\n"))
    end

    def default_source_config_path(project_dir)
      File.join(project_dir, SOURCE_CONFIG)
    end

    def default_source_config(entrypoint = "bin/connect")
      PackageStartConfig.new(command: [entrypoint])
    end

    def render_source_config(config = default_source_config)
      lines = [
        "# Plushie standalone package config.",
        "# Commit this file and edit it when the packaged app needs a",
        "# different entry point or working directory.",
        "",
        "config_version = 1",
        "",
        "[start]",
        "# Structured argv. The first item is the POSIX entry point.",
        "# On windows-* targets the SDK automatically uses bin/connect.cmd.",
        "command = #{toml_array(config.command)}",
        ""
      ]
      lines.join("\n")
    end

    def write_source_config(path, config = default_source_config)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, render_source_config(config))
    end

    def app_has_native_widgets?
      Plushie::Widget::NativeBuild.configured_widgets.any?
    end

    def resolve_renderer!(path: nil, kind: "stock")
      if kind == "stock" && app_has_native_widgets?
        raise Error, "Native widget packaging requires a custom renderer. Use --renderer-kind custom."
      end

      source_path = nil

      if path && !path.empty?
        source_path = path
        ensure_package_tools_available!
      elsif ENV["PLUSHIE_BINARY_PATH"] && !ENV["PLUSHIE_BINARY_PATH"].empty?
        source_path = ENV["PLUSHIE_BINARY_PATH"]
        ensure_package_tools_available!
      elsif kind != "stock"
        raise Error, "Custom renderer packages require --renderer-path or PLUSHIE_BINARY_PATH"
      else
        source_path = Binary.sync_renderer_with_tool!
      end

      unless source_path
        raise Error, "No renderer binary found. Run bundle exec rake plushie:download or set PLUSHIE_BINARY_PATH."
      end

      validate_renderer!(source_path)

      {
        kind: kind,
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

    def run_cli(argv)
      options = {
        project_dir: Dir.pwd,
        output_dir: "dist",
        renderer_kind: "stock",
        entrypoint: "bin/connect",
        package_config: nil,
        write_package_config: false,
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
        opts.on("--icon PATH", "App icon to copy into the payload") { |value| options[:icon_path] = value }
        opts.on("--entrypoint PATH", "Payload app entrypoint") { |value| options[:entrypoint] = value }
        opts.on("--package-config PATH", "Developer-owned package config") { |value| options[:package_config] = value }
        opts.on("--write-package-config", "Write a package config template and exit") { options[:write_package_config] = true }
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

      result = build(**options)
      puts "Wrote #{result.fetch(:manifest_path)}"
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

    def start_command(entrypoint, target = package_target)
      # The payload ships a thin OS-specific wrapper alongside the user's
      # entrypoint (renamed to <entrypoint>.rb). The wrapper invokes the
      # bundled Ruby runtime so the launcher only needs to call one file.
      #
      # POSIX: bin/connect   (shebang script)
      # Windows: bin/connect.cmd  (batch script)
      if windows_target?(target)
        [connect_cmd_name(entrypoint)]
      else
        [entrypoint]
      end
    end

    def windows_target?(target)
      target.to_s.start_with?("windows-")
    end

    def connect_rb_name(entrypoint)
      "#{entrypoint}.rb"
    end

    def connect_cmd_name(entrypoint)
      "#{entrypoint}.cmd"
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

    def copy_app!(project_dir, payload_dir, entrypoint, sdk_source_path, target = package_target)
      copy_required_path(File.join(project_dir, "lib"), File.join(payload_dir, "lib"))
      copy_entrypoint!(project_dir, payload_dir, entrypoint, target)

      if sdk_source_path && !sdk_source_path.empty? && File.directory?(File.join(sdk_source_path, "lib", "plushie"))
        puts "Using local plushie SDK from #{sdk_source_path}"
        vendor_dir = File.join(payload_dir, "vendor", "plushie-ruby")
        FileUtils.mkdir_p(vendor_dir)
        copy_dir_contents(sdk_source_path, vendor_dir)
        FileUtils.rm_rf(File.join(vendor_dir, ".git"))
        File.write(File.join(payload_dir, "Gemfile"), local_sdk_gemfile)
      else
        copy_required_path(File.join(project_dir, "Gemfile"), File.join(payload_dir, "Gemfile"))
      end
    end

    def copy_entrypoint!(project_dir, dest_root, entrypoint, target = package_target)
      # The user's entrypoint script is copied as <entrypoint>.rb so that the
      # OS-specific launcher wrapper can invoke it regardless of target.
      rb_name = connect_rb_name(entrypoint)
      copy_required_path(File.join(project_dir, entrypoint), File.join(dest_root, rb_name))

      if windows_target?(target)
        write_connect_cmd!(dest_root, entrypoint)
      else
        write_connect_sh!(dest_root, entrypoint)
      end
    end

    def write_connect_sh!(dest_root, entrypoint)
      # POSIX shebang wrapper. Resolves the payload root relative to $0 so
      # the launcher can invoke it from any working directory.
      rb_name = connect_rb_name(entrypoint)
      content = <<~SH
        #!/bin/sh
        set -e
        DIR="$(cd "$(dirname "$0")/.." && pwd)"
        exec "$DIR/ruby/bin/ruby" "$DIR/#{rb_name}" "$@"
      SH
      dest = File.join(dest_root, entrypoint)
      File.write(dest, content)
      FileUtils.chmod(0o755, dest)
    end

    def write_connect_cmd!(dest_root, entrypoint)
      # Windows batch wrapper. Resolves the payload root via %~dp0 so the
      # launcher can invoke it from any working directory.
      rb_name = connect_rb_name(entrypoint)
      content = <<~CMD
        @echo off
        setlocal
        set "DIR=%~dp0.."
        "%DIR%\\ruby\\bin\\ruby.exe" "%DIR%\\#{rb_name.tr("/", "\\")}" %*
      CMD
      dest = File.join(dest_root, connect_cmd_name(entrypoint))
      File.write(dest, content)
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

    def toml_string(value)
      JSON.generate(value.to_s)
    end

    def toml_array(values)
      "[" + values.map { |value| toml_string(value) }.join(", ") + "]"
    end
  end
end

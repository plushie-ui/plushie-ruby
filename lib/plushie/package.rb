# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"
require "json"
require "open3"
require "optparse"
require "rbconfig"

require_relative "../plushie"

module Plushie
  # Standalone package payload and manifest helpers.
  module Package
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
      entrypoint: "bin/connect",
      sdk_source_path: ENV["PLUSHIE_RUBY_DIR"],
      bundle_without: "development test"
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

      FileUtils.rm_rf(output_dir)
      FileUtils.mkdir_p(File.join(app_dir, "bin"))
      FileUtils.mkdir_p(File.join(app_dir, "lib"))
      FileUtils.mkdir_p(File.join(app_dir, ".bundle"))
      FileUtils.mkdir_p(File.join(payload_dir, "bin"))
      FileUtils.mkdir_p(ruby_dir)

      copy_ruby_runtime!(ruby_dir)
      copy_app!(project_dir, app_dir, entrypoint, sdk_source_path)
      install_runtime_gems!(app_dir, bundle_without)
      install_renderer!(renderer.fetch(:source_path), File.join(payload_dir, renderer.fetch(:payload_path)))
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
        host_command: host_command(entrypoint),
        working_dir: "app",
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
      host_command:,
      payload_archive:,
      app_name: nil,
      target: nil,
      renderer_kind: "stock",
      renderer_source: "local-resolve",
      working_dir: "."
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
        host_command: host_command,
        working_dir: working_dir,
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
        "renderer_path = #{toml_string(manifest.fetch(:renderer).fetch(:path))}",
        "host_command = #{toml_array(manifest.fetch(:host_command))}",
        "working_dir = #{toml_string(manifest.fetch(:working_dir))}",
        "exec_env = []",
        "",
        "[renderer]",
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
      unless kind == "stock"
        raise Error, "Ruby package helper currently supports stock renderers only"
      end

      source_path = nil
      resolved_source = source

      if path && !path.empty?
        source_path = path
        resolved_source ||= "local-path"
      elsif ENV["PLUSHIE_BINARY_PATH"] && !ENV["PLUSHIE_BINARY_PATH"].empty?
        source_path = ENV["PLUSHIE_BINARY_PATH"]
        resolved_source ||= "local-path"
      elsif (source_path = renderer_from_source_path)
        resolved_source ||= "local-build"
      elsif (source_path = Binary.path)
        resolved_source ||= "local-resolve"
      elsif (source_path = find_executable("plushie-renderer") || find_executable("plushie"))
        resolved_source ||= "local-resolve"
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

    def run_cli(argv)
      options = {
        project_dir: Dir.pwd,
        output_dir: "dist",
        renderer_kind: "stock",
        renderer_source: nil,
        entrypoint: "bin/connect",
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
        opts.on("--entrypoint PATH", "Payload app entrypoint") { |value| options[:entrypoint] = value }
        opts.on("--sdk-source-path DIR", "Local plushie Ruby SDK source to vendor") { |value| options[:sdk_source_path] = value }
        opts.on("--bundle-without GROUPS", "Bundler groups to exclude") { |value| options[:bundle_without] = value }
        opts.on("-h", "--help", "Show help") { show_help = true }
      end

      parser.parse!(argv)
      if show_help
        puts parser
        return
      end

      raise Error, "--app-id is required" unless options[:app_id]

      result = build(**options)
      puts "Wrote #{result.fetch(:archive_path)}"
      puts "Wrote #{result.fetch(:manifest_path)}"
      puts "Build launcher with:"
      puts "  cargo plushie package --manifest #{result.fetch(:manifest_path)} --release"
    end

    def env_value(name, default = nil)
      value = ENV[name]
      (value.nil? || value.empty?) ? default : value
    end

    def build_from_env
      app_id = env_value("PLUSHIE_PACKAGE_APP_ID")
      raise Error, "PLUSHIE_PACKAGE_APP_ID is required" unless app_id

      build(
        app_id: app_id,
        app_name: env_value("PLUSHIE_PACKAGE_APP_NAME"),
        app_version: env_value("PLUSHIE_PACKAGE_APP_VERSION", "0.1.0"),
        project_dir: env_value("PLUSHIE_PACKAGE_PROJECT_DIR", Dir.pwd),
        output_dir: env_value("PLUSHIE_PACKAGE_OUTPUT", "dist"),
        target: env_value("PLUSHIE_PACKAGE_TARGET"),
        renderer_path: env_value("PLUSHIE_PACKAGE_RENDERER_PATH"),
        renderer_kind: env_value("PLUSHIE_PACKAGE_RENDERER_KIND", "stock"),
        renderer_source: env_value("PLUSHIE_PACKAGE_RENDERER_SOURCE"),
        entrypoint: env_value("PLUSHIE_PACKAGE_ENTRYPOINT", "bin/connect"),
        sdk_source_path: env_value("PLUSHIE_RUBY_DIR"),
        bundle_without: env_value("PLUSHIE_PACKAGE_BUNDLE_WITHOUT", "development test")
      )
    end

    def host_command(entrypoint)
      ruby = RbConfig::CONFIG.fetch("ruby_install_name") + RbConfig::CONFIG.fetch("EXEEXT")
      [File.join("ruby", "bin", ruby), entrypoint]
    end

    def renderer_payload_path
      File.join("bin", "plushie-renderer#{RbConfig::CONFIG.fetch("EXEEXT")}")
    end

    def copy_ruby_runtime!(ruby_dir)
      copy_dir_contents(RbConfig::CONFIG.fetch("prefix"), ruby_dir)
    end

    def copy_app!(project_dir, app_dir, entrypoint, sdk_source_path)
      copy_required_path(File.join(project_dir, "lib"), File.join(app_dir, "lib"))
      copy_required_path(File.join(project_dir, entrypoint), File.join(app_dir, entrypoint))
      FileUtils.chmod(0o755, File.join(app_dir, entrypoint))

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
      Dir.chdir(source_path) { run!(%w[cargo build --release -p plushie-renderer]) }
      File.join(source_path, "target", "release", "plushie-renderer#{RbConfig::CONFIG.fetch("EXEEXT")}")
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

    def toml_string(value)
      JSON.generate(value.to_s)
    end

    def toml_array(values)
      "[" + values.map { |value| toml_string(value) }.join(", ") + "]"
    end
  end
end

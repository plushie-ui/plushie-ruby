# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "plushie/package"

class TestPackage < Minitest::Test
  P = Plushie::Package

  def test_normalize_package_target
    assert_equal "linux-x86_64", P.normalize_package_target("Linux", "x86_64")
    assert_equal "darwin-aarch64", P.normalize_package_target("Darwin", "arm64")
    assert_equal "windows-x86_64", P.normalize_package_target("Windows", "AMD64")
  end

  def test_rejects_unknown_package_target_parts
    assert_raises(Plushie::Error) { P.normalize_package_target("plan9", "x86_64") }
    assert_raises(Plushie::Error) { P.normalize_package_target("linux", "riscv64") }
  end

  def test_manifest_for_payload_records_hash_size_and_sdk_metadata
    Dir.mktmpdir do |tmpdir|
      archive = File.join(tmpdir, "payload.tar.zst")
      File.binwrite(archive, "payload")

      manifest = P.manifest_for_payload(
        app_id: "dev.plushie.test",
        app_name: "Test App",
        app_version: "0.1.0",
        target: "linux-x86_64",
        renderer_kind: "custom",
        renderer_path: "bin/plushie-renderer",
        start_command: ["ruby/bin/ruby", "bin/connect"],
        working_dir: ".",
        payload_archive: archive
      )

      assert_equal 7, manifest.fetch(:payload_size)
      assert_equal 64, manifest.fetch(:payload_hash).length
      assert_equal "payload.tar.zst", manifest.fetch(:payload_archive)

      toml = P.render_manifest(manifest)
      assert_includes toml, 'app_name = "Test App"'
      assert_includes toml, 'host_sdk = "ruby"'
      assert_includes toml, "host_sdk_version = \"#{Plushie::VERSION}\""
      assert_includes toml, "plushie_rust_version = \"#{Plushie::PLUSHIE_RUST_VERSION}\""
      assert_includes toml, "protocol_version = #{Plushie::Protocol::PROTOCOL_VERSION}"
      assert_includes toml, "[start]\nworking_dir = \".\""
      assert_includes toml, 'command = ["ruby/bin/ruby", "bin/connect"]'
      assert_includes(
        toml,
        'forward_env = ["PATH", "HOME", "LANG", "LC_ALL", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "DISPLAY"]'
      )
      refute_includes toml, "[platform]"
      assert_includes toml, "[renderer]\npath = \"bin/plushie-renderer\""
      assert_includes toml, 'kind = "custom"'
      assert_includes toml, 'archive = "payload.tar.zst"'
      assert_includes toml, "hash = \"sha256:#{manifest.fetch(:payload_hash)}\""
    end
  end

  def test_manifest_for_payload_accepts_app_icon_path
    Dir.mktmpdir do |tmpdir|
      archive = File.join(tmpdir, "payload.tar.zst")
      File.binwrite(archive, "payload")

      manifest = P.manifest_for_payload(
        app_id: "dev.plushie.test",
        app_version: "0.1.0",
        target: "linux-x86_64",
        renderer_path: "bin/plushie-renderer",
        icon_path: "assets/app.png",
        start_command: ["bin/connect"],
        payload_archive: archive
      )

      assert_equal "assets/app.png", manifest.fetch(:platform).fetch(:icon)
      assert_includes P.render_manifest(manifest), "[platform]\nicon = \"assets/app.png\""
    end
  end

  def test_render_manifest_omits_platform_section_when_no_icon
    Dir.mktmpdir do |tmpdir|
      archive = File.join(tmpdir, "payload.tar.zst")
      File.binwrite(archive, "payload")

      manifest = P.manifest_for_payload(
        app_id: "dev.plushie.test",
        app_version: "0.1.0",
        target: "linux-x86_64",
        renderer_path: "bin/plushie-renderer",
        start_command: ["bin/connect"],
        payload_archive: archive
      )

      toml = P.render_manifest(manifest)
      refute_includes toml, "[platform]"
      refute_includes toml, "icon"
    end
  end

  def test_parse_source_config_accepts_start_config
    config = P.parse_source_config(<<~TOML)
      config_version = 1

      [start]
      working_dir = "app"
      command = ["bin/notes", "--project", "Daily Notes"]
      forward_env = [
        "PATH",
        "HOME",
      ]
    TOML

    assert_equal "app", config.start.working_dir
    assert_equal ["bin/notes", "--project", "Daily Notes"], config.start.command
    assert_equal ["PATH", "HOME"], config.start.forward_env
  end

  def test_render_source_config_uses_real_start_values
    text = P.render_source_config(P.default_source_config("bin/connect"))

    assert_includes text, "config_version = 1"
    assert_includes text, "[start]"
    assert_includes text, 'working_dir = "."'
    assert_includes text, '"bin/connect"'
    assert_includes text, '"WAYLAND_DISPLAY"'
  end

  def test_write_source_config_writes_template
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, "plushie-package.config.toml")

      P.write_source_config(path, P.default_source_config("bin/connect"))

      assert_includes File.read(path), '"bin/connect"'
    end
  end

  def test_parse_source_config_rejects_invalid_start_values
    invalid_configs = [
      <<~TOML,
        config_version = 2

        [start]
        working_dir = "."
        command = ["bin/notes"]
        forward_env = []
      TOML
      <<~TOML,
        config_version = 1

        [start]
        working_dir = "../app"
        command = ["bin/notes"]
        forward_env = []
      TOML
      <<~TOML,
        config_version = 1

        [start]
        working_dir = "."
        command = ["/usr/bin/notes"]
        forward_env = []
      TOML
      <<~TOML,
        config_version = 1

        [start]
        working_dir = "."
        command = ["bin/notes"]
        forward_env = ["PLUSHIE_BINARY_PATH"]
      TOML
      <<~TOML,
        config_version = 1

        [start]
        working_dir = "."
        command = ["bin/notes"]
        forward_env = ["PLUSHIE_PACKAGE_READY_FILE"]
      TOML
      <<~TOML
        config_version = 1

        [start]
        working_dir = "."
        command = []
        forward_env = []
      TOML
    ]

    invalid_configs.each do |text|
      assert_raises(Plushie::Error) { P.parse_source_config(text) }
    end
  end

  def test_resolve_start_config_uses_default_source_config_when_present
    Dir.mktmpdir do |tmpdir|
      File.write(File.join(tmpdir, "plushie-package.config.toml"), <<~TOML)
        config_version = 1

        [start]
        working_dir = "app"
        command = ["bin/notes"]
        forward_env = ["PATH"]
      TOML

      config = P.resolve_start_config(tmpdir, nil, "bin/connect")

      assert_equal "app", config.working_dir
      assert_equal ["bin/notes"], config.command
      assert_equal ["PATH"], config.forward_env
    end
  end

  def test_resolve_start_config_keeps_default_without_source_config
    Dir.mktmpdir do |tmpdir|
      config = P.resolve_start_config(tmpdir, nil, "bin/connect")

      assert_equal ".", config.working_dir
      assert_equal P.start_command("bin/connect"), config.command
      assert_equal P::DEFAULT_FORWARD_ENV, config.forward_env
    end
  end

  def test_write_manifest_creates_parent_directories
    Dir.mktmpdir do |tmpdir|
      archive = File.join(tmpdir, "payload.tar.zst")
      File.binwrite(archive, "payload")
      manifest = P.manifest_for_payload(
        app_id: "dev.plushie.test",
        app_version: "0.1.0",
        target: "linux-x86_64",
        renderer_path: "bin/plushie-renderer",
        start_command: ["bin/connect"],
        payload_archive: archive
      )

      output = File.join(tmpdir, "dist", "package", "plushie-package.toml")
      P.write_manifest(output, manifest)

      assert_equal P.render_manifest(manifest), File.read(output)
    end
  end

  def test_resolve_renderer_records_explicit_paths_as_local_paths
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "plushie-renderer")
      write_executable(renderer)

      with_package_tools(tmpdir) do
        result = P.resolve_renderer!(path: renderer)

        assert_equal renderer, result.fetch(:source_path)
      end
    end
  end

  def test_resolve_renderer_allows_custom_renderer_with_explicit_path
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "custom-renderer")
      write_executable(renderer)

      with_package_tools(tmpdir) do
        result = P.resolve_renderer!(path: renderer, kind: "custom")

        assert_equal "custom", result.fetch(:kind)
        assert_equal renderer, result.fetch(:source_path)
      end
    end
  end

  def test_resolve_renderer_allows_custom_renderer_from_binary_path
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "custom-renderer")
      write_executable(renderer)

      with_package_tools(tmpdir) do
        with_env("PLUSHIE_BINARY_PATH" => renderer) do
          result = P.resolve_renderer!(kind: "custom")

          assert_equal "custom", result.fetch(:kind)
          assert_equal renderer, result.fetch(:source_path)
        end
      end
    end
  end

  def test_resolve_renderer_rejects_custom_renderer_without_explicit_path
    Dir.mktmpdir do |tmpdir|
      with_package_tools(tmpdir) do
        with_env("PLUSHIE_BINARY_PATH" => nil, "PLUSHIE_RUST_SOURCE_PATH" => nil) do
          error = assert_raises(Plushie::Error) { P.resolve_renderer!(kind: "custom") }

          assert_match(/Custom renderer packages require/, error.message)
        end
      end
    end
  end

  def test_resolve_renderer_requires_managed_package_tools_for_explicit_paths
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "plushie-renderer")
      write_executable(renderer)

      Dir.chdir(tmpdir) do
        error = assert_raises(Plushie::Error) { P.resolve_renderer!(path: renderer) }
        assert_match(/managed Plushie tool set/, error.message)
      end
    end
  end

  def test_resolve_renderer_records_environment_paths_as_local_paths
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "plushie-renderer")
      write_executable(renderer)

      with_package_tools(tmpdir) do
        with_env("PLUSHIE_BINARY_PATH" => renderer) do
          result = P.resolve_renderer!

          assert_equal renderer, result.fetch(:source_path)
        end
      end
    end
  end

  def test_resolve_renderer_syncs_managed_tool_set_for_stock_packages
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "bin", "plushie-renderer")
      FileUtils.mkdir_p(File.dirname(renderer))
      write_executable(renderer)

      with_env("PLUSHIE_BINARY_PATH" => nil, "PLUSHIE_RUST_SOURCE_PATH" => nil) do
        with_binary_method(:sync_renderer_with_tool!, renderer) do
          result = P.resolve_renderer!

          assert_equal renderer, result.fetch(:source_path)
        end
      end
    end
  end

  def test_resolve_ruby_runtime_root_supports_path_provider
    Dir.mktmpdir do |tmpdir|
      assert_equal tmpdir, P.resolve_ruby_runtime_root(provider: "path", root: tmpdir)
    end
  end

  def test_resolve_ruby_runtime_root_rejects_missing_path
    assert_raises(Plushie::Error) do
      P.resolve_ruby_runtime_root(provider: "path")
    end
  end

  def test_resolve_ruby_runtime_root_supports_mise_provider
    status = Struct.new(:success?).new(true)

    P.stub(:require_command, nil) do
      Open3.stub(:capture3, [" /opt/mise/ruby \n", "", status]) do
        assert_equal "/opt/mise/ruby", P.resolve_ruby_runtime_root(provider: "mise", version: "3.3.6")
      end
    end
  end

  def test_materialize_default_icons_invokes_cargo_plushie
    Dir.mktmpdir do |tmpdir|
      assets = File.join(tmpdir, "payload", "assets")
      commands = []

      with_env("PLUSHIE_RUST_SOURCE_PATH" => nil) do
        with_package_method(:run!, ->(command) { commands << command }) do
          P.materialize_default_icons!(assets)
        end
      end

      assert_equal [[File.join("bin", Plushie::Binary.tool_name), "default-icons", "--out", assets]], commands
      assert File.directory?(assets)
    end
  end

  def test_materialize_default_icons_uses_source_checkout_resolver_shape
    Dir.mktmpdir do |tmpdir|
      assets = File.join(tmpdir, "payload", "assets")
      manifest = File.join(tmpdir, "plushie-rust", "Cargo.toml")
      FileUtils.mkdir_p(File.dirname(manifest))
      File.write(manifest, "[workspace]\n")
      command = nil

      with_env("PLUSHIE_RUST_SOURCE_PATH" => File.dirname(manifest)) do
        with_package_method(:run!, ->(value) { command = value }) do
          P.materialize_default_icons!(assets)
        end
      end

      assert_equal [
        "cargo", "run", "--manifest-path", manifest, "-p", "cargo-plushie", "--bin", "plushie",
        "--release", "--quiet", "--", "default-icons", "--out", assets
      ], command
    end
  end

  def test_install_package_icons_uses_default_icon
    Dir.mktmpdir do |tmpdir|
      payload = File.join(tmpdir, "payload")

      with_package_method(:materialize_default_icons!, ->(assets) { FileUtils.mkdir_p(assets) }) do
        icon = P.install_package_icons!(payload, tmpdir, nil)

        assert_equal "assets/default-app-icon-512.png", icon
      end
    end
  end

  def test_install_package_icons_copies_app_icon
    Dir.mktmpdir do |tmpdir|
      icon_path = File.join(tmpdir, "app-icon.png")
      File.binwrite(icon_path, "icon")
      payload = File.join(tmpdir, "payload")

      with_package_method(:materialize_default_icons!, ->(assets) { FileUtils.mkdir_p(assets) }) do
        icon = P.install_package_icons!(payload, tmpdir, icon_path)

        assert_equal "assets/app-icon.png", icon
        assert_equal "icon", File.binread(File.join(payload, "assets", "app-icon.png"))
      end
    end
  end

  def test_run_cli_accepts_icon_option
    captured = nil
    result = {
      archive_path: "dist/payload.tar.zst",
      manifest_path: "dist/plushie-package.toml"
    }

    P.stub(:build, ->(**options) {
      captured = options
      result
    }) do
      capture_io do
        P.run_cli(["--app-id", "dev.plushie.test", "--icon", "icons/app.png"])
      end
    end

    assert_equal "icons/app.png", captured.fetch(:icon_path)
  end

  def test_run_cli_accepts_package_config_option
    captured = nil
    result = {
      archive_path: "dist/payload.tar.zst",
      manifest_path: "dist/plushie-package.toml"
    }

    P.stub(:build, ->(**options) {
      captured = options
      result
    }) do
      capture_io do
        P.run_cli(["--app-id", "dev.plushie.test", "--package-config", "packaging.toml"])
      end
    end

    assert_equal "packaging.toml", captured.fetch(:package_config)
  end

  def test_run_cli_prints_portable_handoff
    result = {
      archive_path: "dist/payload.tar.zst",
      manifest_path: "dist/plushie-package.toml"
    }

    P.stub(:build, result) do
      stdout, = capture_io do
        P.run_cli(["--app-id", "dev.plushie.test"])
      end

      assert_includes stdout, "Build launcher with:"
      assert_includes stdout, "  bin/plushie package portable --manifest dist/plushie-package.toml"
    end
  end

  def test_run_cli_accepts_ruby_runtime_provider_options
    captured = nil
    result = {
      archive_path: "dist/payload.tar.zst",
      manifest_path: "dist/plushie-package.toml"
    }

    P.stub(:build, ->(**options) {
      captured = options
      result
    }) do
      capture_io do
        P.run_cli([
          "--app-id", "dev.plushie.test",
          "--ruby-provider", "mise",
          "--ruby-version", "3.3.6"
        ])
      end
    end

    assert_equal "mise", captured.fetch(:ruby_provider)
    assert_equal "3.3.6", captured.fetch(:ruby_version)
  end

  def test_run_cli_writes_package_config_without_app_id
    Dir.mktmpdir do |tmpdir|
      capture_io do
        P.run_cli(["--project-dir", tmpdir, "--write-package-config"])
      end

      assert_includes File.read(File.join(tmpdir, "plushie-package.config.toml")), '"bin/connect"'
    end
  end

  def test_build_from_env_accepts_icon_path
    captured = nil
    result = {
      archive_path: "dist/payload.tar.zst",
      manifest_path: "dist/plushie-package.toml"
    }

    with_env(
      "PLUSHIE_PACKAGE_APP_ID" => "dev.plushie.test",
      "PLUSHIE_PACKAGE_ICON_PATH" => "icons/app.png"
    ) do
      P.stub(:build, ->(**options) {
        captured = options
        result
      }) do
        assert_equal result, P.build_from_env
      end
    end

    assert_equal "icons/app.png", captured.fetch(:icon_path)
  end

  def test_build_from_env_accepts_package_config
    captured = nil
    result = {
      archive_path: "dist/payload.tar.zst",
      manifest_path: "dist/plushie-package.toml"
    }

    with_env(
      "PLUSHIE_PACKAGE_APP_ID" => "dev.plushie.test",
      "PLUSHIE_PACKAGE_CONFIG" => "packaging.toml"
    ) do
      P.stub(:build, ->(**options) {
        captured = options
        result
      }) do
        assert_equal result, P.build_from_env
      end
    end

    assert_equal "packaging.toml", captured.fetch(:package_config)
  end

  def test_build_from_env_accepts_ruby_runtime_provider
    captured = nil
    result = {
      archive_path: "dist/payload.tar.zst",
      manifest_path: "dist/plushie-package.toml"
    }

    with_env(
      "PLUSHIE_PACKAGE_APP_ID" => "dev.plushie.test",
      "PLUSHIE_RUBY_PROVIDER" => "path",
      "PLUSHIE_RUBY_ROOT" => "/opt/ruby"
    ) do
      P.stub(:build, ->(**options) {
        captured = options
        result
      }) do
        assert_equal result, P.build_from_env
      end
    end

    assert_equal "path", captured.fetch(:ruby_provider)
    assert_equal "/opt/ruby", captured.fetch(:ruby_root)
  end

  def test_env_flag_accepts_boolean_spellings
    with_env("PLUSHIE_PACKAGE_STRICT_TOOLS" => "yes") do
      assert_equal true, P.env_flag("PLUSHIE_PACKAGE_STRICT_TOOLS")
    end

    with_env("PLUSHIE_PACKAGE_STRICT_TOOLS" => "off") do
      assert_equal false, P.env_flag("PLUSHIE_PACKAGE_STRICT_TOOLS", true)
    end
  end

  def test_env_flag_rejects_ambiguous_values
    with_env("PLUSHIE_PACKAGE_STRICT_TOOLS" => "maybe") do
      assert_raises(Plushie::Error) { P.env_flag("PLUSHIE_PACKAGE_STRICT_TOOLS") }
    end
  end

  def test_build_from_env_accepts_overrides
    captured = nil
    result = {
      archive_path: "dist/payload.tar.zst",
      manifest_path: "dist/plushie-package.toml"
    }

    with_env("PLUSHIE_PACKAGE_APP_ID" => nil) do
      P.stub(:build, ->(**options) {
        captured = options
        result
      }) do
        assert_equal result, P.build_from_env(
          app_id: "dev.plushie.test",
          app_name: "Test App",
          app_version: "0.2.0"
        )
      end
    end

    assert_equal "dev.plushie.test", captured.fetch(:app_id)
    assert_equal "Test App", captured.fetch(:app_name)
    assert_equal "0.2.0", captured.fetch(:app_version)
  end

  def test_copy_app_uses_configured_command_entrypoint
    Dir.mktmpdir do |tmpdir|
      project = File.join(tmpdir, "project")
      payload = File.join(tmpdir, "payload")
      FileUtils.mkdir_p(File.join(project, "lib"))
      FileUtils.mkdir_p(File.join(project, "bin"))
      File.write(File.join(project, "Gemfile"), "source \"https://rubygems.org\"\n")
      File.write(File.join(project, "bin", "notes"), "#!/bin/sh\n")
      start = P::PackageStartConfig.new(
        working_dir: ".",
        command: ["bin/notes"],
        forward_env: []
      )

      P.copy_app!(project, payload, start, "bin/connect", nil)

      assert File.exist?(File.join(payload, "bin", "notes"))
      refute File.exist?(File.join(payload, "bin", "connect"))
    end
  end

  private

  def write_executable(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, path)
  end

  def with_package_tools(tmpdir)
    write_executable(File.join(tmpdir, "bin", Plushie::Binary.tool_name))
    write_executable(File.join(tmpdir, "bin", Plushie::Binary.launcher_name))
    Dir.chdir(tmpdir) { yield }
  end

  def with_package_method(name, implementation)
    singleton = P.singleton_class
    had_original = singleton.method_defined?(name)
    original = singleton.instance_method(name) if had_original
    singleton.send(:remove_method, name) if had_original
    if implementation.respond_to?(:call)
      singleton.define_method(name, implementation)
    else
      singleton.define_method(name) { |*_args, **_kwargs| implementation }
    end
    yield
  ensure
    singleton.send(:remove_method, name)
    singleton.define_method(name, original) if had_original
  end

  def with_binary_method(name, implementation)
    singleton = Plushie::Binary.singleton_class
    had_original = singleton.method_defined?(name)
    original = singleton.instance_method(name) if had_original
    singleton.send(:remove_method, name) if had_original
    if implementation.respond_to?(:call)
      singleton.define_method(name, implementation)
    else
      singleton.define_method(name) { |*_args, **_kwargs| implementation }
    end
    yield
  ensure
    singleton.send(:remove_method, name)
    singleton.define_method(name, original) if had_original
  end

  def with_env(values)
    old_values = values.to_h { |key, _value| [key, ENV[key]] }
    values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
    yield
  ensure
    old_values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end

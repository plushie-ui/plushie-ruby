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
        renderer_source: "local-build",
        renderer_path: "bin/plushie-renderer",
        start_command: ["ruby/bin/ruby", "bin/connect"],
        working_dir: "app",
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
      assert_includes toml, "[start]\nworking_dir = \"app\""
      assert_includes toml, 'command = ["ruby/bin/ruby", "bin/connect"]'
      assert_includes(
        toml,
        'forward_env = ["PATH", "HOME", "LANG", "LC_ALL", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "DISPLAY"]'
      )
      assert_includes toml, "[platform]\nicon = \"assets/plushie-checkbox-512x512.png\""
      assert_includes toml, "[renderer]\npath = \"bin/plushie-renderer\""
      assert_includes toml, 'kind = "custom"'
      assert_includes toml, 'source = "local-build"'
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
      assert_includes P.render_manifest(manifest), 'icon = "assets/app.png"'
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
    assert_includes text, 'working_dir = "app"'
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

      assert_equal "app", config.working_dir
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

      result = P.resolve_renderer!(path: renderer)

      assert_equal "local-path", result.fetch(:source)
      assert_equal renderer, result.fetch(:source_path)
    end
  end

  def test_resolve_renderer_preserves_explicit_source
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "plushie-renderer")
      write_executable(renderer)

      result = P.resolve_renderer!(path: renderer, source: "test-fixture")

      assert_equal "test-fixture", result.fetch(:source)
    end
  end

  def test_resolve_renderer_records_environment_paths_as_local_paths
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "plushie-renderer")
      write_executable(renderer)

      with_env("PLUSHIE_BINARY_PATH" => renderer) do
        result = P.resolve_renderer!

        assert_equal "local-path", result.fetch(:source)
        assert_equal renderer, result.fetch(:source_path)
      end
    end
  end

  def test_resolve_renderer_records_source_builds_as_local_builds
    Dir.mktmpdir do |tmpdir|
      renderer = File.join(tmpdir, "target", "release", "plushie-renderer")
      write_executable(renderer)

      with_env("PLUSHIE_RUST_SOURCE_PATH" => tmpdir, "PLUSHIE_BINARY_PATH" => nil) do
        P.stub(:renderer_from_source_path, renderer) do
          result = P.resolve_renderer!

          assert_equal "local-build", result.fetch(:source)
          assert_equal renderer, result.fetch(:source_path)
        end
      end
    end
  end

  def test_materialize_default_icons_invokes_cargo_plushie
    Dir.mktmpdir do |tmpdir|
      assets = File.join(tmpdir, "payload", "assets")
      commands = []

      Plushie::CargoPlushie.stub(:resolve, ["cargo-plushie", []]) do
        P.stub(:run!, ->(command) { commands << command }) do
          P.materialize_default_icons!(assets)
        end
      end

      assert_equal [["cargo-plushie", "default-icons", "--out", assets]], commands
      assert File.directory?(assets)
    end
  end

  def test_materialize_default_icons_uses_source_checkout_resolver_shape
    Dir.mktmpdir do |tmpdir|
      assets = File.join(tmpdir, "payload", "assets")
      manifest = File.join(tmpdir, "plushie-rust", "Cargo.toml")
      command = nil

      resolver = [
        "cargo",
        ["run", "--manifest-path", manifest, "-p", "cargo-plushie", "--"]
      ]

      Plushie::CargoPlushie.stub(:resolve, resolver) do
        P.stub(:run!, ->(value) { command = value }) do
          P.materialize_default_icons!(assets)
        end
      end

      assert_equal [
        "cargo", "run", "--manifest-path", manifest, "-p", "cargo-plushie",
        "--", "default-icons", "--out", assets
      ], command
    end
  end

  def test_install_package_icons_uses_default_icon
    Dir.mktmpdir do |tmpdir|
      payload = File.join(tmpdir, "payload")

      P.stub(:materialize_default_icons!, ->(assets) { FileUtils.mkdir_p(assets) }) do
        icon = P.install_package_icons!(payload, tmpdir, nil)

        assert_equal "assets/plushie-checkbox-512x512.png", icon
      end
    end
  end

  def test_install_package_icons_copies_app_icon
    Dir.mktmpdir do |tmpdir|
      icon_path = File.join(tmpdir, "app-icon.png")
      File.binwrite(icon_path, "icon")
      payload = File.join(tmpdir, "payload")

      P.stub(:materialize_default_icons!, ->(assets) { FileUtils.mkdir_p(assets) }) do
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
      app = File.join(payload, "app")
      FileUtils.mkdir_p(File.join(project, "lib"))
      FileUtils.mkdir_p(File.join(project, "bin"))
      File.write(File.join(project, "Gemfile"), "source \"https://rubygems.org\"\n")
      File.write(File.join(project, "bin", "notes"), "#!/bin/sh\n")
      start = P::PackageStartConfig.new(
        working_dir: ".",
        command: ["bin/notes"],
        forward_env: []
      )

      P.copy_app!(project, payload, app, start, "bin/connect", nil)

      assert File.exist?(File.join(payload, "bin", "notes"))
      refute File.exist?(File.join(app, "bin", "connect"))
    end
  end

  private

  def write_executable(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, path)
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

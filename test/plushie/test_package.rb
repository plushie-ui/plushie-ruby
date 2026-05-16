# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "plushie/package"
require "plushie/widget/native_build"

# Minimal native widget used only by package rejection tests.
class FakeNativeWidgetForPackageTest
  include Plushie::Widget

  widget :fake_native_pkg, kind: :native_widget
  rust_crate "native/fake"
  rust_constructor "fake::Fake::new()"
end

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

  def test_start_command_uses_posix_wrapper_for_linux
    assert_equal ["bin/connect"], P.start_command("bin/connect", "linux-x86_64")
  end

  def test_start_command_uses_cmd_wrapper_for_windows
    assert_equal ["bin/connect.cmd"], P.start_command("bin/connect", "windows-x86_64")
  end

  def test_write_partial_manifest_emits_required_fields
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, "plushie-package.toml")

      P.write_partial_manifest(
        path,
        app_id: "dev.plushie.test",
        app_name: "Test App",
        app_version: "0.1.0",
        target: "linux-x86_64",
        renderer_kind: "stock",
        renderer_path: "bin/plushie-renderer",
        start_command: ["bin/connect"]
      )

      toml = File.read(path)
      assert_includes toml, "schema_version = 1"
      assert_includes toml, 'app_id = "dev.plushie.test"'
      assert_includes toml, 'app_name = "Test App"'
      assert_includes toml, 'app_version = "0.1.0"'
      assert_includes toml, 'target = "linux-x86_64"'
      assert_includes toml, 'host_sdk = "ruby"'
      assert_includes toml, "host_sdk_version = \"#{Plushie::VERSION}\""
      assert_includes toml, "plushie_rust_version = \"#{Plushie::PLUSHIE_RUST_VERSION}\""
      assert_includes toml, "protocol_version = #{Plushie::Protocol::PROTOCOL_VERSION}"
      assert_includes toml, "[start]"
      assert_includes toml, 'command = ["bin/connect"]'
      assert_includes toml, "[renderer]"
      assert_includes toml, 'path = "bin/plushie-renderer"'
      assert_includes toml, 'kind = "stock"'
    end
  end

  def test_write_partial_manifest_omits_app_name_when_nil
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, "plushie-package.toml")

      P.write_partial_manifest(
        path,
        app_id: "dev.plushie.test",
        app_version: "0.1.0",
        target: "linux-x86_64",
        renderer_kind: "stock",
        renderer_path: "bin/plushie-renderer",
        start_command: ["bin/connect"]
      )

      toml = File.read(path)
      refute_includes toml, "app_name"
    end
  end

  def test_write_partial_manifest_uses_cmd_for_windows_start_command
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, "plushie-package.toml")

      P.write_partial_manifest(
        path,
        app_id: "dev.plushie.test",
        app_version: "0.1.0",
        target: "windows-x86_64",
        renderer_kind: "stock",
        renderer_path: "bin/plushie-renderer.exe",
        start_command: ["bin/connect.cmd"]
      )

      toml = File.read(path)
      assert_includes toml, 'command = ["bin/connect.cmd"]'
    end
  end

  def test_write_partial_manifest_creates_parent_directories
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, "dist", "package", "plushie-package.toml")

      P.write_partial_manifest(
        path,
        app_id: "dev.plushie.test",
        app_version: "0.1.0",
        target: "linux-x86_64",
        renderer_kind: "stock",
        renderer_path: "bin/plushie-renderer",
        start_command: ["bin/connect"]
      )

      assert File.exist?(path)
    end
  end

  def test_render_source_config_includes_start_block
    toml = P.render_source_config
    assert_includes toml, "config_version = 1"
    assert_includes toml, "[start]"
    assert_includes toml, 'command = ["bin/connect"]'
  end

  def test_render_source_config_includes_commented_assets_block
    toml = P.render_source_config
    assert_includes toml, "# [assets]"
    assert_includes toml, '# dir = "package_assets"'
    # The block must be commented out by default so absence of the
    # section triggers the package_assets/ convention.
    refute_match(/^\[assets\]/, toml)
    refute_match(/^dir = /, toml)
  end

  def test_partial_manifest_has_no_payload_section
    Dir.mktmpdir do |tmpdir|
      path = File.join(tmpdir, "plushie-package.toml")

      P.write_partial_manifest(
        path,
        app_id: "dev.plushie.test",
        app_version: "0.1.0",
        target: "linux-x86_64",
        renderer_kind: "stock",
        renderer_path: "bin/plushie-renderer",
        start_command: ["bin/connect"]
      )

      toml = File.read(path)
      refute_includes toml, "[payload]"
      refute_includes toml, "working_dir"
      refute_includes toml, "forward_env"
    end
  end

  def test_resolve_renderer_rejects_stock_with_native_widgets
    # A stock renderer cannot embed native (Rust-backed) widgets.
    # The check must fire before any payload directory is created.
    Dir.mktmpdir do |tmpdir|
      output_dir = File.join(tmpdir, "dist")

      with_env("PLUSHIE_WIDGETS" => "FakeNativeWidgetForPackageTest") do
        error = assert_raises(Plushie::Error) do
          P.resolve_renderer!(kind: "stock")
        end

        assert_match(/Native widget packaging requires a custom renderer/, error.message)
        assert_match(/--renderer-kind custom/, error.message)
        refute File.exist?(output_dir), "payload directory must not be created before the check fails"
      end
    end
  end

  def test_build_shells_to_assemble_with_manifest_and_payload_dir
    Dir.mktmpdir do |tmpdir|
      project = setup_minimal_project(tmpdir)
      renderer = File.join(tmpdir, "renderer")
      write_executable(renderer)

      assemble_calls = []

      with_package_tools(tmpdir) do
        with_env("PLUSHIE_BINARY_PATH" => renderer) do
          with_package_method(:install_runtime_gems!, ->(_dir, _without) {}) do
            with_package_method(:copy_ruby_runtime!, ->(_dir, **_kwargs) {}) do
              with_package_method(:run!, ->(cmd) { assemble_calls << cmd }) do
                P.build(
                  app_id: "dev.plushie.test",
                  project_dir: project,
                  output_dir: File.join(tmpdir, "dist"),
                  target: "linux-x86_64"
                )
              end
            end
          end
        end
      end

      assert_equal 1, assemble_calls.length
      cmd = assemble_calls.first
      assert_equal File.join("bin", Plushie::Binary.tool_name), cmd[0]
      assert_equal "package", cmd[1]
      assert_equal "assemble", cmd[2]
      assert_includes cmd, "--manifest"
      assert_includes cmd, "--payload-dir"
    end
  end

  def test_build_forwards_package_config_to_assemble
    Dir.mktmpdir do |tmpdir|
      project = setup_minimal_project(tmpdir)
      renderer = File.join(tmpdir, "renderer")
      write_executable(renderer)
      config_path = File.join(project, "my-package.toml")
      File.write(config_path, "config_version = 1\n")

      assemble_calls = []

      with_package_tools(tmpdir) do
        with_env("PLUSHIE_BINARY_PATH" => renderer) do
          with_package_method(:install_runtime_gems!, ->(_dir, _without) {}) do
            with_package_method(:copy_ruby_runtime!, ->(_dir, **_kwargs) {}) do
              with_package_method(:run!, ->(cmd) { assemble_calls << cmd }) do
                P.build(
                  app_id: "dev.plushie.test",
                  project_dir: project,
                  output_dir: File.join(tmpdir, "dist"),
                  target: "linux-x86_64",
                  package_config: "my-package.toml"
                )
              end
            end
          end
        end
      end

      cmd = assemble_calls.first
      config_idx = cmd.index("--package-config")
      refute_nil config_idx, "expected --package-config in assemble args"
      assert_equal config_path, cmd[config_idx + 1]
    end
  end

  def test_build_omits_package_config_arg_when_not_set
    Dir.mktmpdir do |tmpdir|
      project = setup_minimal_project(tmpdir)
      renderer = File.join(tmpdir, "renderer")
      write_executable(renderer)

      assemble_calls = []

      with_package_tools(tmpdir) do
        with_env("PLUSHIE_BINARY_PATH" => renderer) do
          with_package_method(:install_runtime_gems!, ->(_dir, _without) {}) do
            with_package_method(:copy_ruby_runtime!, ->(_dir, **_kwargs) {}) do
              with_package_method(:run!, ->(cmd) { assemble_calls << cmd }) do
                P.build(
                  app_id: "dev.plushie.test",
                  project_dir: project,
                  output_dir: File.join(tmpdir, "dist"),
                  target: "linux-x86_64"
                )
              end
            end
          end
        end
      end

      cmd = assemble_calls.first
      refute_includes cmd, "--package-config"
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

  def test_run_cli_accepts_icon_option
    captured = nil
    result = {manifest_path: "dist/plushie-package.toml"}

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
    result = {manifest_path: "dist/plushie-package.toml"}

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

  def test_run_cli_accepts_ruby_runtime_provider_options
    captured = nil
    result = {manifest_path: "dist/plushie-package.toml"}

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

  def test_run_cli_prints_manifest_path
    result = {manifest_path: "dist/plushie-package.toml"}

    P.stub(:build, result) do
      stdout, = capture_io do
        P.run_cli(["--app-id", "dev.plushie.test"])
      end

      assert_includes stdout, "dist/plushie-package.toml"
    end
  end

  def test_build_from_env_accepts_icon_path
    captured = nil
    result = {manifest_path: "dist/plushie-package.toml"}

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
    result = {manifest_path: "dist/plushie-package.toml"}

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
    result = {manifest_path: "dist/plushie-package.toml"}

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
    result = {manifest_path: "dist/plushie-package.toml"}

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

  def test_copy_app_copies_entrypoint_as_rb_and_generates_posix_wrapper
    Dir.mktmpdir do |tmpdir|
      project = File.join(tmpdir, "project")
      payload = File.join(tmpdir, "payload")
      FileUtils.mkdir_p(File.join(project, "lib"))
      FileUtils.mkdir_p(File.join(project, "bin"))
      File.write(File.join(project, "Gemfile"), "source \"https://rubygems.org\"\n")
      File.write(File.join(project, "bin", "connect"), "# entrypoint\n")

      P.copy_app!(project, payload, "bin/connect", nil, "linux-x86_64")

      assert File.exist?(File.join(payload, "bin", "connect.rb"))
      assert File.exist?(File.join(payload, "bin", "connect"))
      assert_includes File.read(File.join(payload, "bin", "connect")), "ruby/bin/ruby"
      refute File.exist?(File.join(payload, "bin", "connect.cmd"))
    end
  end

  def test_copy_app_generates_cmd_wrapper_for_windows_target
    Dir.mktmpdir do |tmpdir|
      project = File.join(tmpdir, "project")
      payload = File.join(tmpdir, "payload")
      FileUtils.mkdir_p(File.join(project, "lib"))
      FileUtils.mkdir_p(File.join(project, "bin"))
      File.write(File.join(project, "Gemfile"), "source \"https://rubygems.org\"\n")
      File.write(File.join(project, "bin", "connect"), "# entrypoint\n")

      P.copy_app!(project, payload, "bin/connect", nil, "windows-x86_64")

      assert File.exist?(File.join(payload, "bin", "connect.rb"))
      assert File.exist?(File.join(payload, "bin", "connect.cmd"))
      cmd = File.read(File.join(payload, "bin", "connect.cmd"))
      assert_includes cmd, "ruby.exe"
      assert_includes cmd, "connect.rb"
      refute File.exist?(File.join(payload, "bin", "connect"))
    end
  end

  private

  def setup_minimal_project(tmpdir)
    project = File.join(tmpdir, "project")
    FileUtils.mkdir_p(File.join(project, "lib"))
    FileUtils.mkdir_p(File.join(project, "bin"))
    File.write(File.join(project, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(project, "bin", "connect"), "# entrypoint\n")
    project
  end

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

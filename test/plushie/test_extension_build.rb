# frozen_string_literal: true

require "test_helper"
require "plushie/widget/native_build"

# A fake native widget for testing the build pipeline.
class FakeSparkline
  include Plushie::Widget

  widget :sparkline, kind: :native_widget
  rust_crate "native/sparkline"
  rust_constructor "sparkline::SparklineExt::new()"

  prop :data, :any, default: []
  prop :color, :color, default: :blue
end

# A second native widget for multi-widget coverage.
class FakeChart
  include Plushie::Widget

  widget :chart, kind: :native_widget
  rust_crate "native/chart"
  rust_constructor "chart::ChartExt::new()"

  prop :series, :any, default: []
end

class TestExtensionBuild < Minitest::Test
  Build = Plushie::Widget::NativeBuild

  def build_binary_name(name)
    Gem.win_platform? ? "#{name}.exe" : name
  end

  # -- Crate path resolution --

  def test_resolve_crate_paths_returns_absolute_paths
    paths = Build.resolve_crate_paths([FakeSparkline], base_dir: "/home/user/project")
    assert_equal "/home/user/project/native/sparkline", paths[FakeSparkline]
  end

  # Path traversal is blocked before we hand anything to cargo-plushie
  # so a malicious widget config can't point cargo at arbitrary files.
  def test_resolve_crate_paths_rejects_traversal_outside_project
    escape_ext = Class.new do
      include Plushie::Widget

      widget :evil, kind: :native_widget
      rust_crate "../../etc/shadow"
      rust_constructor "evil::Evil::new()"
    end

    err = assert_raises(Plushie::Error) do
      Build.resolve_crate_paths([escape_ext], base_dir: "/home/user/project")
    end
    assert_includes err.message, "outside the allowed directory"
  end

  # -- Widget class declarations --

  def test_native_widget_class_reports_native
    assert FakeSparkline.native?
  end

  def test_native_widget_has_crate_path
    assert_equal "native/sparkline", FakeSparkline.native_crate
  end

  def test_native_widget_has_constructor
    assert_equal "sparkline::SparklineExt::new()", FakeSparkline.rust_constructor_expr
  end

  def test_pure_widget_is_not_native
    klass = Class.new do
      include Plushie::Widget

      widget :gauge
      prop :value, :number, default: 0
    end
    klass.finalize!
    refute klass.native?
  end

  def test_native_widget_missing_rust_crate_raises
    assert_raises(ArgumentError) do
      Class.new do
        include Plushie::Widget

        widget :bad_native, kind: :native_widget
        rust_constructor "bad::Bad::new()"
        finalize!
      end
    end
  end

  def test_native_widget_missing_rust_constructor_raises
    assert_raises(ArgumentError) do
      Class.new do
        include Plushie::Widget

        widget :bad_native, kind: :native_widget
        rust_crate "native/bad"
        finalize!
      end
    end
  end

  def test_invalid_widget_kind_raises
    assert_raises(ArgumentError) do
      Class.new do
        include Plushie::Widget

        widget :bad, kind: :something_else
      end
    end
  end

  # -- configured_widgets --

  def test_configured_widgets_returns_empty_without_env
    old_val = ENV.delete("PLUSHIE_WIDGETS")
    begin
      assert_equal [], Build.configured_widgets
    ensure
      ENV["PLUSHIE_WIDGETS"] = old_val if old_val
    end
  end

  def test_configured_widgets_returns_empty_for_blank_string
    ENV["PLUSHIE_WIDGETS"] = "  "
    begin
      assert_equal [], Build.configured_widgets
    ensure
      ENV.delete("PLUSHIE_WIDGETS")
    end
  end

  def test_configured_widgets_resolves_class_names
    ENV["PLUSHIE_WIDGETS"] = "FakeSparkline"
    begin
      exts = Build.configured_widgets
      assert_equal [FakeSparkline], exts
    ensure
      ENV.delete("PLUSHIE_WIDGETS")
    end
  end

  def test_configured_widgets_filters_non_native
    klass = Class.new do
      include Plushie::Widget

      widget :gauge
      prop :value, :number, default: 0
    end
    Object.const_set(:TestPureGaugeForBuild, klass) unless defined?(TestPureGaugeForBuild)

    ENV["PLUSHIE_WIDGETS"] = "TestPureGaugeForBuild"
    begin
      # Non-native widgets are filtered out (with a warning), not rejected
      result = Build.configured_widgets
      assert_equal [], result
    ensure
      ENV.delete("PLUSHIE_WIDGETS")
    end
  end

  # -- Widget metadata verification --

  # cargo-plushie discovers widgets via `cargo metadata` and the
  # [package.metadata.plushie.widget] table. The Ruby SDK's pre-flight
  # fails with the widget class name (not a cargo_metadata dump) when
  # a crate is missing that table so the author knows exactly where to
  # add it.
  def test_verify_widget_metadata_passes_when_table_present
    Dir.mktmpdir do |tmpdir|
      crate_dir = File.join(tmpdir, "sparkline")
      FileUtils.mkdir_p(crate_dir)
      File.write(File.join(crate_dir, "Cargo.toml"), <<~TOML)
        [package]
        name = "sparkline"
        version = "0.1.0"

        [package.metadata.plushie.widget]
        type_name = "sparkline"
        constructor = "sparkline::SparklineExt::new()"
      TOML

      # Should not raise
      Build.verify_widget_metadata!({FakeSparkline => crate_dir})
    end
  end

  def test_verify_widget_metadata_raises_when_table_missing
    Dir.mktmpdir do |tmpdir|
      crate_dir = File.join(tmpdir, "sparkline")
      FileUtils.mkdir_p(crate_dir)
      File.write(File.join(crate_dir, "Cargo.toml"), <<~TOML)
        [package]
        name = "sparkline"
        version = "0.1.0"
      TOML

      err = assert_raises(Plushie::Error) do
        Build.verify_widget_metadata!({FakeSparkline => crate_dir})
      end
      assert_includes err.message, "FakeSparkline"
      assert_includes err.message, "[package.metadata.plushie.widget]"
    end
  end

  def test_verify_widget_metadata_raises_when_required_keys_missing
    Dir.mktmpdir do |tmpdir|
      crate_dir = File.join(tmpdir, "sparkline")
      FileUtils.mkdir_p(crate_dir)
      # Header present but missing `constructor`
      File.write(File.join(crate_dir, "Cargo.toml"), <<~TOML)
        [package]
        name = "sparkline"
        version = "0.1.0"

        [package.metadata.plushie.widget]
        type_name = "sparkline"
      TOML

      err = assert_raises(Plushie::Error) do
        Build.verify_widget_metadata!({FakeSparkline => crate_dir})
      end
      assert_includes err.message, "FakeSparkline"
    end
  end

  def test_verify_widget_metadata_raises_when_crate_missing
    err = assert_raises(Plushie::Error) do
      Build.verify_widget_metadata!({FakeSparkline => "/definitely/not/here"})
    end
    assert_includes err.message, "FakeSparkline"
    assert_includes err.message, "not found"
  end

  # -- Virtual manifest generation --

  # The virtual manifest hands cargo-plushie a dep graph it can walk.
  # Widget crates show up as path deps, and the binary name override
  # travels through [package.metadata.plushie].
  def test_write_virtual_manifest_lists_widget_path_deps
    Dir.mktmpdir do |tmpdir|
      crate_paths = {FakeSparkline => File.join(tmpdir, "native", "sparkline")}
      FileUtils.mkdir_p(crate_paths[FakeSparkline])

      Build.write_virtual_manifest(tmpdir, "plushie-custom", crate_paths)

      toml = File.read(File.join(tmpdir, "Cargo.toml"))
      assert_includes toml, "[package]"
      assert_includes toml, %(name = "plushie_custom")
      assert_includes toml, "[dependencies]"
      assert_includes toml, "sparkline = { path ="
      assert_includes toml, "[package.metadata.plushie]"
      assert_includes toml, %(binary_name = "plushie-custom")

      # An empty lib.rs lets cargo compile the virtual crate.
      assert File.exist?(File.join(tmpdir, "src", "lib.rs"))
    end
  end

  def test_write_virtual_manifest_handles_zero_widgets
    Dir.mktmpdir do |tmpdir|
      Build.write_virtual_manifest(tmpdir, "plushie-renderer", {})
      toml = File.read(File.join(tmpdir, "Cargo.toml"))
      assert_includes toml, "[dependencies]"
      refute_match(/= \{ path =/, toml)
    end
  end

  # -- Binary location --

  # cargo-plushie writes the renderer workspace under
  # `target/plushie-renderer/` and builds into that workspace's own
  # `target/` so the final path is nested. Keep this in sync with
  # cargo-plushie's cmd_run / cmd_build output.
  def test_locate_built_binary_uses_cargo_plushie_layout
    path = Build.locate_built_binary("/scratch", "plushie-custom", true)
    assert_equal "/scratch/target/plushie-renderer/target/release/plushie-custom",
      path.sub(/\.exe\z/, "")

    debug = Build.locate_built_binary("/scratch", "plushie-custom", false)
    assert_includes debug, "/target/plushie-renderer/target/debug/"
  end

  def test_locate_built_binary_respects_cargo_target_dir
    original = ENV["CARGO_TARGET_DIR"]
    ENV["CARGO_TARGET_DIR"] = "/custom/target"
    begin
      path = Build.locate_built_binary("/scratch", "plushie-custom", true)
      assert_includes path, "/custom/target/plushie-renderer/target/release/"
    ensure
      original ? ENV["CARGO_TARGET_DIR"] = original : ENV.delete("CARGO_TARGET_DIR")
    end
  end

  def test_locate_built_binary_prefers_cargo_plushie_layout
    Dir.mktmpdir do |scratch|
      binary = build_binary_name("plushie-custom")
      preferred = File.join(scratch, "target", "plushie-renderer", "target", "release", binary)
      fallback = File.join(scratch, "target", "other-layout", "release", binary)
      FileUtils.mkdir_p(File.dirname(preferred))
      FileUtils.mkdir_p(File.dirname(fallback))
      File.write(preferred, "")
      File.write(fallback, "")

      assert_equal preferred, Build.locate_built_binary(scratch, "plushie-custom", true)
    end
  end

  def test_locate_built_binary_falls_back_to_discovered_profile_binary
    Dir.mktmpdir do |scratch|
      fallback = File.join(scratch, "target", "cargo-plushie-new-layout", "release", build_binary_name("plushie-custom"))
      FileUtils.mkdir_p(File.dirname(fallback))
      File.write(fallback, "")

      assert_equal fallback, Build.locate_built_binary(scratch, "plushie-custom", true)
    end
  end

  def test_locate_built_binary_searches_cargo_target_dir
    Dir.mktmpdir do |scratch|
      Dir.mktmpdir do |target_dir|
        original = ENV["CARGO_TARGET_DIR"]
        ENV["CARGO_TARGET_DIR"] = target_dir
        fallback = File.join(target_dir, "generated", "debug", build_binary_name("plushie-custom"))
        FileUtils.mkdir_p(File.dirname(fallback))
        File.write(fallback, "")

        assert_equal fallback, Build.locate_built_binary(scratch, "plushie-custom", false)
      ensure
        original ? ENV["CARGO_TARGET_DIR"] = original : ENV.delete("CARGO_TARGET_DIR")
      end
    end
  end

  def test_locate_built_binary_raises_on_ambiguous_fallbacks
    Dir.mktmpdir do |scratch|
      first = File.join(scratch, "target", "layout-a", "release", build_binary_name("plushie-custom"))
      second = File.join(scratch, "target", "layout-b", "release", build_binary_name("plushie-custom"))
      [first, second].each do |path|
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "")
      end

      error = assert_raises(Plushie::Error) do
        Build.locate_built_binary(scratch, "plushie-custom", true)
      end
      assert_includes error.message, "multiple built binaries named"
    end
  end

  def test_locate_built_binary_returns_preferred_path_when_not_found
    Dir.mktmpdir do |scratch|
      expected = File.join(scratch, "target", "plushie-renderer", "target", "debug", build_binary_name("plushie-custom"))
      assert_equal expected, Build.locate_built_binary(scratch, "plushie-custom", false)
    end
  end
end

# frozen_string_literal: true

require "test_helper"
require "plushie/widget/native_build"

# A fake native extension for testing the build pipeline.
class FakeSparkline
  include Plushie::Widget

  widget :sparkline, kind: :native_widget
  rust_crate "native/sparkline"
  rust_constructor "sparkline::SparklineExt::new()"

  prop :data, :any, default: []
  prop :color, :color, default: :blue
end

# A second native extension for collision testing.
class FakeChart
  include Plushie::Widget

  widget :chart, kind: :native_widget
  rust_crate "native/chart"
  rust_constructor "chart::ChartExt::new()"

  prop :series, :any, default: []
end

# Extension with a duplicate type name (sparkline) for collision testing.
class FakeSparklineDupe
  include Plushie::Widget

  widget :sparkline, kind: :native_widget
  rust_crate "native/sparkline_v2"
  rust_constructor "sparkline_v2::SparklineExt::new()"

  prop :data, :any, default: []
end

# Extension with duplicate crate basename for crate collision testing.
class FakeChartSameCrate
  include Plushie::Widget

  widget :pie_chart, kind: :native_widget
  rust_crate "other/chart"
  rust_constructor "other_chart::PieChartExt::new()"

  prop :slices, :any, default: []
end

class TestExtensionBuild < Minitest::Test
  Build = Plushie::Widget::NativeBuild

  # -- Collision detection --

  def test_check_collisions_passes_with_unique_types
    Build.check_collisions!([FakeSparkline, FakeChart])
  end

  def test_check_collisions_raises_on_duplicate_type_names
    err = assert_raises(Plushie::Error) do
      Build.check_collisions!([FakeSparkline, FakeSparklineDupe])
    end
    assert_includes err.message, "sparkline"
    assert_includes err.message, "FakeSparkline"
    assert_includes err.message, "FakeSparklineDupe"
  end

  def test_check_crate_name_collisions_passes_with_unique_names
    Build.check_crate_name_collisions!([FakeSparkline, FakeChart])
  end

  def test_check_crate_name_collisions_raises_on_duplicate_basenames
    err = assert_raises(Plushie::Error) do
      Build.check_crate_name_collisions!([FakeChart, FakeChartSameCrate])
    end
    assert_includes err.message, "chart"
    assert_includes err.message, "FakeChart"
    assert_includes err.message, "FakeChartSameCrate"
  end

  # -- Crate path resolution --

  def test_resolve_crate_paths_returns_absolute_paths
    paths = Build.resolve_crate_paths([FakeSparkline], base_dir: "/home/user/project")
    assert_equal "/home/user/project/native/sparkline", paths[FakeSparkline]
  end

  def test_resolve_crate_paths_rejects_traversal_outside_project
    # Create a class with a crate path that escapes the base dir
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

  # -- Rust constructor validation --

  def test_validate_rust_constructor_accepts_simple_path
    Build.validate_rust_constructor!(FakeSparkline, "MyExt::new()")
  end

  def test_validate_rust_constructor_accepts_identifier
    Build.validate_rust_constructor!(FakeSparkline, "MyExt")
  end

  def test_validate_rust_constructor_accepts_nested_path
    Build.validate_rust_constructor!(FakeSparkline, "sparkline::ext::SparklineExt::new()")
  end

  def test_validate_rust_constructor_rejects_semicolons
    err = assert_raises(Plushie::Error) do
      Build.validate_rust_constructor!(FakeSparkline, "MyExt::new(); drop_tables()")
    end
    assert_includes err.message, "invalid characters"
  end

  def test_validate_rust_constructor_rejects_braces
    err = assert_raises(Plushie::Error) do
      Build.validate_rust_constructor!(FakeSparkline, "MyExt { field: 1 }")
    end
    assert_includes err.message, "invalid characters"
  end

  def test_validate_rust_constructor_rejects_empty_string
    err = assert_raises(Plushie::Error) do
      Build.validate_rust_constructor!(FakeSparkline, "")
    end
    assert_includes err.message, "invalid characters"
  end

  # -- Cargo.toml generation --

  def test_generate_cargo_toml_with_source_path
    Dir.mktmpdir do |tmpdir|
      # Create fake source dirs so the check passes
      FileUtils.mkdir_p(File.join(tmpdir, "source", "plushie-ext"))
      FileUtils.mkdir_p(File.join(tmpdir, "source", "plushie-renderer"))
      FileUtils.mkdir_p(File.join(tmpdir, "native", "sparkline"))

      build_dir = File.join(tmpdir, "_build", "plushie", "custom")
      FileUtils.mkdir_p(build_dir)

      crate_paths = {FakeSparkline => File.join(tmpdir, "native", "sparkline")}

      ENV["PLUSHIE_SOURCE_PATH"] = File.join(tmpdir, "source")
      begin
        toml = Build.generate_cargo_toml(build_dir, "plushie-custom", [FakeSparkline], crate_paths)
      ensure
        ENV.delete("PLUSHIE_SOURCE_PATH")
      end

      assert_includes toml, "[package]"
      assert_includes toml, "plushie_custom"
      assert_includes toml, 'edition = "2024"'
      assert_includes toml, "plushie-custom"
      assert_includes toml, "plushie-ext = { path ="
      assert_includes toml, "plushie-renderer = { path ="
      assert_includes toml, "sparkline = { path ="
    end
  end

  def test_generate_cargo_toml_without_source_path
    build_dir = "/tmp/test_build"
    crate_paths = {FakeSparkline => "/home/user/project/native/sparkline"}

    old_val = ENV.delete("PLUSHIE_SOURCE_PATH")
    begin
      toml = Build.generate_cargo_toml(build_dir, "plushie-custom", [FakeSparkline], crate_paths)
    ensure
      ENV["PLUSHIE_SOURCE_PATH"] = old_val if old_val
    end

    assert_includes toml, %(plushie-ext = "#{Plushie::BINARY_VERSION}")
    assert_includes toml, %(plushie-renderer = "#{Plushie::BINARY_VERSION}")
  end

  def test_generate_cargo_toml_uses_project_version
    build_dir = "/tmp/test_build"
    crate_paths = {FakeSparkline => "/home/user/project/native/sparkline"}

    old_val = ENV.delete("PLUSHIE_SOURCE_PATH")
    begin
      toml = Build.generate_cargo_toml(build_dir, "plushie-custom", [FakeSparkline], crate_paths)
    ensure
      ENV["PLUSHIE_SOURCE_PATH"] = old_val if old_val
    end

    assert_includes toml, %(version = "#{Plushie::VERSION}")
  end

  # -- main.rs generation --

  def test_generate_main_rs_contains_builder
    rs = Build.generate_main_rs([FakeSparkline])
    assert_includes rs, "PlushieAppBuilder::new()"
    assert_includes rs, "plushie_renderer::run(builder)"
    assert_includes rs, ".extension(sparkline::SparklineExt::new())"
  end

  def test_generate_main_rs_with_multiple_extensions
    rs = Build.generate_main_rs([FakeSparkline, FakeChart])
    assert_includes rs, ".extension(sparkline::SparklineExt::new())"
    assert_includes rs, ".extension(chart::ChartExt::new())"
  end

  def test_generate_main_rs_includes_comment
    rs = Build.generate_main_rs([FakeSparkline])
    assert_includes rs, "Auto-generated by rake plushie:build"
    assert_includes rs, "Do not edit manually"
  end

  # -- Extension class declarations --

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

  def test_configured_widgets_rejects_non_native
    klass = Class.new do
      include Plushie::Widget

      widget :gauge
      prop :value, :number, default: 0
    end
    # Assign a name we can look up
    Object.const_set(:TestPureGaugeForBuild, klass) unless defined?(TestPureGaugeForBuild)

    ENV["PLUSHIE_WIDGETS"] = "TestPureGaugeForBuild"
    begin
      assert_raises(Plushie::Error) do
        Build.configured_widgets
      end
    ensure
      ENV.delete("PLUSHIE_WIDGETS")
    end
  end
end

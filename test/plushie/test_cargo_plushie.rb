# frozen_string_literal: true

require "test_helper"

class TestCargoPlushie < Minitest::Test
  Resolver = Plushie::CargoPlushie

  def setup
    @orig_env = ENV.delete("PLUSHIE_RUST_SOURCE_PATH")
    @orig_source_path = Plushie.configuration.source_path
    Plushie.configuration.source_path = nil
  end

  def teardown
    if @orig_env
      ENV["PLUSHIE_RUST_SOURCE_PATH"] = @orig_env
    else
      ENV.delete("PLUSHIE_RUST_SOURCE_PATH")
    end
    Plushie.configuration.source_path = @orig_source_path
  end

  # Source path takes priority over anything on PATH. The returned
  # command drives cargo-plushie out of the local checkout via
  # `cargo run -p cargo-plushie`, so contributors never need to
  # reinstall after pulling plushie-rust.
  def test_resolve_uses_cargo_run_when_source_path_is_set
    Dir.mktmpdir do |tmpdir|
      ENV["PLUSHIE_RUST_SOURCE_PATH"] = tmpdir
      program, args = Resolver.resolve

      assert_equal "cargo", program
      assert_includes args, "run"
      assert_includes args, "-p"
      assert_includes args, "cargo-plushie"
      assert_includes args, "--release"
      assert_includes args, "--quiet"
      assert_includes args, "--"
      assert_includes args, "--manifest-path"
      assert_includes args, File.join(tmpdir, "Cargo.toml")
    end
  end

  # Missing source directory falls through to the PATH lookup, so the
  # env var can stay set without poisoning a system install.
  def test_resolve_falls_through_when_source_path_directory_missing
    ENV["PLUSHIE_RUST_SOURCE_PATH"] = "/definitely/not/a/real/path"
    stub_capture3(stdout: "cargo-plushie #{Plushie::PLUSHIE_RUST_VERSION}\n", status: 0) do
      program, args = Resolver.resolve
      assert_equal "cargo-plushie", program
      assert_equal [], args
    end
  end

  # Matching version on PATH yields a plain "cargo-plushie" invocation
  # with no preamble; the shell command is the binary plus the user's
  # args.
  def test_resolve_uses_path_binary_when_version_matches
    stub_capture3(stdout: "cargo-plushie #{Plushie::PLUSHIE_RUST_VERSION}\n", status: 0) do
      program, args = Resolver.resolve
      assert_equal "cargo-plushie", program
      assert_equal [], args
    end
  end

  # Version mismatch is actionable: the message includes the exact
  # `cargo install` command and the PLUSHIE_RUST_SOURCE_PATH escape hatch.
  def test_resolve_raises_on_version_mismatch
    stub_capture3(stdout: "cargo-plushie 0.0.1\n", status: 0) do
      err = assert_raises(Plushie::Error) { Resolver.resolve }
      assert_includes err.message, "not version #{Plushie::PLUSHIE_RUST_VERSION}"
      assert_includes err.message,
        "cargo install cargo-plushie --version #{Plushie::PLUSHIE_RUST_VERSION} --locked"
      assert_includes err.message, "PLUSHIE_RUST_SOURCE_PATH"
    end
  end

  # Binary missing from PATH (Errno::ENOENT) surfaces as a clear error
  # with install guidance; we don't leak the raw Errno.
  def test_resolve_raises_when_cargo_plushie_missing
    stub_capture3(raise: Errno::ENOENT.new) do
      err = assert_raises(Plushie::Error) { Resolver.resolve }
      assert_includes err.message, "cargo-plushie not found on PATH"
      assert_includes err.message,
        "cargo install cargo-plushie --version #{Plushie::PLUSHIE_RUST_VERSION} --locked"
      assert_includes err.message, "PLUSHIE_RUST_SOURCE_PATH"
    end
  end

  # Garbage output is treated the same as "not installed": we fail
  # loudly rather than trust a version string we couldn't parse.
  def test_resolve_raises_when_version_output_unparseable
    stub_capture3(stdout: "", status: 0) do
      assert_raises(Plushie::Error) { Resolver.resolve }
    end
  end

  # extract_version handles the canonical single-line format and
  # whitespace-padded variants without pulling in a parser.
  def test_extract_version_pulls_version
    assert_equal "0.6.1", Resolver.extract_version("cargo-plushie 0.6.1\n")
    assert_equal "1.2.3", Resolver.extract_version("  cargo-plushie 1.2.3  ")
    assert_equal "0.6.1", Resolver.extract_version("cargo-plushie 0.6.1 (x86_64)")
    assert_equal "1.2.3-beta.1+build.5", Resolver.extract_version("cargo-plushie 1.2.3-beta.1+build.5")
  end

  def test_extract_version_returns_nil_for_empty_output
    assert_nil Resolver.extract_version("")
  end

  def test_extract_version_returns_nil_for_garbage_output
    assert_nil Resolver.extract_version("cargo-plushie nightly build")
    assert_nil Resolver.extract_version("cargo-plushie 1.2.3-")
    assert_nil Resolver.extract_version("cargo-plushie 1.2.3..")
    assert_nil Resolver.extract_version("cargo-plushie 1.2.3-pre.")
  end

  # Stub Open3.capture3 on the CargoPlushie module for the duration of
  # the block. Either raise on call (simulating a missing binary) or
  # return a (stdout, stderr, status) triple.
  def stub_capture3(stdout: "", stderr: "", status: 0, raise: nil)
    fake_status = Struct.new(:success?).new(status == 0)
    Open3.stub(:capture3, ->(*args) {
      raise(raise) if raise
      [stdout, stderr, fake_status]
    }) do
      yield
    end
  end
end

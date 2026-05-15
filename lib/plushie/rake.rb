# frozen_string_literal: true

# Load Plushie Rake tasks.
#
# Add to your Rakefile:
#   require "plushie/rake"
#
# Available tasks:
#   plushie:download : download precompiled renderer binary or WASM
#   plushie:build    : build renderer from Rust source
#   plushie:run      : run a Plushie app
#   plushie:connect  : connect to a renderer via stdio or PLUSHIE_SOCKET
#   plushie:package  : build standalone package payload and manifest
#   plushie:inspect  : print UI tree as JSON
#   plushie:script   : run .plushie test scripts
#   plushie:replay   : replay a .plushie script with real windows
#   plushie:preflight: run all CI checks

require "fileutils"
require "rake"

namespace :plushie do
  desc "Download precompiled plushie binary and/or WASM (args: force; config: artifacts, bin_file, wasm_dir)"
  task :download, [:arg1] do |_t, args|
    require "plushie"

    config = Plushie.configuration
    force = args[:arg1] == "force"
    artifacts = config.artifacts

    if artifacts.include?(:bin)
      bin_file = ENV["PLUSHIE_BIN_FILE"] || config.bin_file
      existing = if bin_file
        File.exist?(bin_file) ? bin_file : nil
      else
        Plushie::Binary.downloaded_path
      end

      if !force && existing
        puts "Binary already exists at #{existing}. Use force to re-download."
      else
        dest = if bin_file
          Plushie::Binary.download!(dest: bin_file)
        else
          Plushie::Binary.sync_renderer_with_tool!(force: force)
        end
        puts "Downloaded plushie binary to #{dest}"
      end
    end

    if artifacts.include?(:wasm)
      wasm_dir = ENV["PLUSHIE_WASM_DIR"] || config.wasm_dir
      Plushie::Binary.download_wasm!(force: force, dir: wasm_dir)
      puts "WASM files installed to #{wasm_dir || Plushie::Binary.wasm_path}"
    end
  end

  desc "Build the plushie renderer (args: release, update; e.g. rake plushie:build[release] or plushie:build[update])"
  task :build, [:arg1, :arg2] do |_t, args|
    require "plushie"

    flags = [args[:arg1], args[:arg2]].compact
    release = flags.include?("release")
    update = flags.include?("update")

    # Verify cargo is available
    unless system("cargo --version", out: File::NULL, err: File::NULL)
      abort "cargo not found. Install Rust via https://rustup.rs"
    end

    # Unified build: always generate a workspace. Stock builds (no
    # native widgets) produce a vanilla plushie-renderer. Custom builds
    # include each widget's Rust crate. Both work with crates.io deps
    # (no source checkout needed) or local source if available.
    require "plushie/widget/native_build"
    widgets = Plushie::Widget::NativeBuild.configured_widgets

    Plushie::Widget::NativeBuild.build_with_widgets(
      widgets, release: release, update: update
    )
  end

  desc "Remove build artifacts (workspace, compiled binary, Cargo target)"
  task :clean do
    require "plushie/widget/native_build"
    Plushie::Widget::NativeBuild.clean!
  end

  desc "Run a Plushie app (e.g. rake plushie:run[Counter] or plushie:run[Counter,dev] or plushie:run[Counter,json])"
  task :run, [:app_class, :opt1, :opt2] do |_t, args|
    unless args[:app_class]
      abort "Usage: rake plushie:run[AppClass] or plushie:run[AppClass,dev] or plushie:run[AppClass,json]"
    end
    require "plushie"

    app_class = Object.const_get(args[:app_class])
    opts = {}

    flags = [args[:opt1], args[:opt2]].compact
    opts[:dev] = true if flags.include?("dev")
    opts[:format] = :json if flags.include?("json")

    Plushie.run(app_class, **opts)
  end

  desc "Connect a standalone app entrypoint via PLUSHIE_SOCKET or spawned renderer"
  task :connect, [:app_class] do |_t, args|
    unless args[:app_class]
      abort "Usage: rake plushie:connect[AppClass]"
    end
    require "plushie"
    app_class = Object.const_get(args[:app_class])
    format = (ENV["PLUSHIE_FORMAT"] == "json") ? :json : :msgpack
    if ENV["PLUSHIE_SOCKET"] && !ENV["PLUSHIE_SOCKET"].empty?
      Plushie.connect(app_class, format: format)
    else
      Plushie.run(app_class, format: format)
    end
  end

  desc "Build standalone package payload and manifest"
  task :package, [:app_id, :app_name, :app_version] do |_t, args|
    require "plushie/package"

    overrides = {}
    overrides[:app_id] = args[:app_id] if args[:app_id]
    overrides[:app_name] = args[:app_name] if args[:app_name]
    overrides[:app_version] = args[:app_version] if args[:app_version]

    begin
      result = Plushie::Package.build_from_env(overrides)
    rescue Plushie::Error => e
      abort e.message
    end

    puts "Wrote #{result.fetch(:archive_path)}"
    puts "Wrote #{result.fetch(:manifest_path)}"
    puts "Build launcher with:"
    puts "  bin/plushie package portable --manifest #{result.fetch(:manifest_path)}"
  end

  desc "Print the initial UI tree as JSON"
  task :inspect, [:app_class] do |_t, args|
    unless args[:app_class]
      abort "Usage: rake plushie:inspect[AppClass]"
    end
    require "plushie"
    require "json"
    app_class = Object.const_get(args[:app_class])
    app = app_class.new
    model = app.init({})
    model = model.is_a?(Array) ? model.first : model
    tree = Plushie::Tree.normalize(app.view(model))
    node = tree.is_a?(Array) ? tree.first : tree
    wire = Plushie::Tree.node_to_wire(node)
    puts JSON.pretty_generate(wire)
  end

  desc "Run .plushie test scripts from test/scripts/"
  task :script, [:path] do |_t, args|
    require "plushie"
    require "plushie/test"

    paths = if args[:path]
      [args[:path]]
    else
      Dir.glob("test/scripts/**/*.plushie")
    end

    if paths.empty?
      puts "No .plushie scripts found"
      exit 0
    end

    passes = 0
    failures = 0

    paths.each do |path|
      puts "Running #{path}..."

      unless File.exist?(path)
        warn "  File not found: #{path}"
        failures += 1
        next
      end

      script = Plushie::Test::Script.parse_file(path)

      if script.instructions.empty?
        puts "  SKIP (empty script)"
        next
      end

      begin
        runner = Plushie::Test::Script::Runner.new(script)
        runner.run
        puts "  PASS"
        passes += 1
      rescue => e
        warn "  FAIL: #{e.message}"
        failures += 1
      end
    end

    puts "\n#{passes} passed, #{failures} failed"
    exit 1 if failures > 0
  end

  desc "Replay a .plushie script with real windows"
  task :replay, [:path] do |_t, args|
    unless args[:path]
      abort "Usage: rake plushie:replay[path/to/script.plushie]"
    end

    require "plushie"
    require "plushie/test"

    path = args[:path]
    unless File.exist?(path)
      abort "Script not found: #{path}"
    end

    puts "Replaying #{path}..."

    script = Plushie::Test::Script.parse_file(path)

    if script.instructions.empty?
      puts "Empty script, nothing to replay."
      exit 0
    end

    # Force windowed backend for replay
    pool = Plushie::Test::SessionPool.new(
      mode: :windowed,
      format: :msgpack,
      max_sessions: 1,
      binary: Plushie::Binary.path!
    )
    pool.start

    begin
      runner = Plushie::Test::Script::Runner.new(script, pool: pool)
      runner.run
      puts "Replay complete."
    ensure
      pool.stop
    end
  end

  desc "Run all CI checks (mirrors .github/workflows/ci.yml)"
  task :preflight do
    require "plushie"

    # When PLUSHIE_RUST_SOURCE_PATH points at a plushie-rust checkout,
    # rebuild plushie-renderer from that source first and export
    # PLUSHIE_BINARY_PATH so the headless test run uses the fresh binary.
    # Tests exercise the real renderer over the wire, so a stale binary
    # hides real bugs and surfaces phantom ones. Without the variable
    # set, the existing binary resolution chain runs unchanged.
    if (source = ENV["PLUSHIE_RUST_SOURCE_PATH"]) && !source.empty?
      workspace = File.expand_path(source)
      manifest = File.join(workspace, "Cargo.toml")
      unless File.exist?(manifest)
        abort "PLUSHIE_RUST_SOURCE_PATH=#{source} but no Cargo.toml at #{manifest}"
      end
      puts "==> cargo build -p plushie-renderer (from #{workspace})"
      Dir.chdir(workspace) do
        sh "cargo build --release -p plushie-renderer"
      end
      ext = Gem.win_platform? ? ".exe" : ""
      binary = File.join(workspace, "target", "release", "plushie-renderer#{ext}")
      unless File.exist?(binary)
        abort "cargo build succeeded but #{binary} is missing"
      end
      ENV["PLUSHIE_BINARY_PATH"] = binary
      puts "    using #{binary}"
    end

    sh "bundle exec rake standard"
    sh "bundle exec rake test"
    # Run headless backend tests to catch renderer integration bugs
    # that mock mode misses. Requires the renderer binary.
    if Plushie::Binary.resolve
      sh "PLUSHIE_TEST_BACKEND=headless bundle exec rake test"
    else
      puts "Skipping headless tests (renderer binary not found)"
    end
    sh "bundle exec steep check"
    sh "bundle exec yard doc"
    puts "\nAll checks passed."
  end
end

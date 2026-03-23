# frozen_string_literal: true

# Load Plushie Rake tasks.
#
# Add to your Rakefile:
#   require "plushie/rake"
#
# Available tasks:
#   plushie:download  -- download precompiled renderer binary or WASM
#   plushie:build     -- build renderer from Rust source
#   plushie:run       -- run a Plushie app
#   plushie:connect   -- connect to a renderer via stdio
#   plushie:inspect   -- print UI tree as JSON
#   plushie:script    -- run .plushie test scripts
#   plushie:replay    -- replay a .plushie script with real windows
#   plushie:preflight -- run all CI checks

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
      if !force && !bin_file && Plushie::Binary.downloaded_path
        puts "Binary already exists at #{Plushie::Binary.downloaded_path}. Use force to re-download."
      else
        dest = Plushie::Binary.download!(dest: bin_file)
        puts "Downloaded plushie binary to #{dest}"
      end
    end

    if artifacts.include?(:wasm)
      wasm_dir = ENV["PLUSHIE_WASM_DIR"] || config.wasm_dir
      Plushie::Binary.download_wasm!(force: force, dir: wasm_dir)
      puts "WASM files installed to #{wasm_dir || Plushie::Binary.wasm_path}"
    end
  end

  desc "Build the plushie renderer from Rust source (with extensions if configured)"
  task :build, [:profile] do |_t, args|
    require "plushie"

    profile = args[:profile] || "debug"
    release = (profile == "release")

    # Verify cargo is available
    unless system("cargo --version", out: File::NULL, err: File::NULL)
      abort "cargo not found. Install Rust via https://rustup.rs"
    end

    # Check for configured extensions
    require "plushie/extension/build"
    extensions = Plushie::Extension::Build.configured_extensions

    if extensions.any?
      Plushie::Extension::Build.build_with_extensions(
        extensions, release: release
      )
    else
      # Stock build: requires source checkout
      source_dir = ENV["PLUSHIE_SOURCE_PATH"] || Plushie.configuration.source_path
      unless source_dir && File.directory?(source_dir)
        abort "Plushie Rust source not found. Set PLUSHIE_SOURCE_PATH env var " \
          "or Plushie.configuration.source_path to the plushie repo checkout."
      end

      cmd_args = ["cargo", "build", "-p", "plushie-renderer"]
      cmd_args << "--release" if release

      label = release ? " (release)" : ""
      puts "Building plushie#{label}..."

      unless system(*cmd_args, chdir: source_dir)
        abort "cargo build failed"
      end

      puts "Build succeeded."

      # Install binary
      profile_dir = release ? "release" : "debug"
      src = File.join(source_dir, "target", profile_dir, "plushie-renderer")

      unless File.exist?(src)
        abort "Build succeeded but binary not found at #{src}"
      end

      bin_file = ENV["PLUSHIE_BIN_FILE"] || Plushie.configuration.bin_file
      if bin_file
        dest = bin_file
        FileUtils.mkdir_p(File.dirname(dest))
      else
        dest_dir = File.join("_build", "plushie", "bin")
        FileUtils.mkdir_p(dest_dir)
        dest = File.join(dest_dir, Plushie::Binary.binary_name)
      end
      FileUtils.cp(src, dest)
      File.chmod(0o755, dest)

      puts "Installed to #{dest}"
    end
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

  desc "Connect to a renderer via stdio (for plushie --exec)"
  task :connect, [:app_class] do |_t, args|
    unless args[:app_class]
      abort "Usage: rake plushie:connect[AppClass]"
    end
    require "plushie"
    app_class = Object.const_get(args[:app_class])
    Plushie.run(app_class, transport: :stdio)
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
    sh "bundle exec rake standard"
    sh "bundle exec rake test"
    sh "bundle exec steep check"
    sh "bundle exec yard doc"
    puts "\nAll checks passed."
  end
end

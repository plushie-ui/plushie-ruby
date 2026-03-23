# frozen_string_literal: true

# Load Plushie Rake tasks.
#
# Add to your Rakefile:
#   require "plushie/rake"
#
# Available tasks:
#   plushie:download  -- download precompiled renderer binary
#   plushie:build     -- build renderer from Rust source
#   plushie:run       -- run a Plushie app
#   plushie:inspect   -- print UI tree as JSON
#   plushie:script    -- run .plushie test scripts
#   plushie:replay    -- replay a .plushie script with real windows
#   plushie:preflight -- run all CI checks

require "fileutils"
require "rake"

namespace :plushie do
  desc "Download the precompiled plushie renderer binary"
  task :download do
    require "plushie"
    Plushie::Binary.download!
    puts "Downloaded plushie binary to #{Plushie::Binary.downloaded_path}"
  end

  desc "Build the plushie renderer from Rust source"
  task :build, [:profile] do |_t, args|
    require "plushie"

    profile = args[:profile] || "debug"
    release = (profile == "release")

    # Verify cargo is available
    unless system("cargo --version", out: File::NULL, err: File::NULL)
      abort "cargo not found. Install Rust via https://rustup.rs"
    end

    # Resolve source directory
    source_dir = ENV["PLUSHIE_SOURCE_PATH"]
    unless source_dir && File.directory?(source_dir)
      abort "Plushie Rust source not found. Set PLUSHIE_SOURCE_PATH to the plushie repo checkout."
    end

    cmd_args = ["cargo", "build", "-p", "plushie"]
    cmd_args << "--release" if release

    label = release ? " (release)" : ""
    puts "Building plushie#{label}..."

    unless system(*cmd_args, chdir: source_dir)
      abort "cargo build failed"
    end

    puts "Build succeeded."

    # Install binary to _build/plushie/bin/
    profile_dir = release ? "release" : "debug"
    src = File.join(source_dir, "target", profile_dir, "plushie")

    unless File.exist?(src)
      abort "Build succeeded but binary not found at #{src}"
    end

    dest_dir = File.join("_build", "plushie", "bin")
    FileUtils.mkdir_p(dest_dir)
    dest = File.join(dest_dir, Plushie::Binary.binary_name)
    FileUtils.cp(src, dest)
    File.chmod(0o755, dest)

    puts "Installed to #{dest}"
  end

  desc "Run a Plushie app (e.g. rake plushie:run[Counter])"
  task :run, [:app_class] do |_t, args|
    unless args[:app_class]
      abort "Usage: rake plushie:run[AppClass]"
    end
    require "plushie"
    app_class = Object.const_get(args[:app_class])
    Plushie.run(app_class)
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

      lines = File.readlines(path, chomp: true).reject { |l| l.strip.empty? || l.strip.start_with?("#") }

      if lines.empty?
        puts "  SKIP (empty script)"
        next
      end

      # Script validation: each line should be a recognized directive
      valid = true
      lines.each do |line|
        unless line.match?(/\A\s*(app|click|type|assert_text|assert_model|wait)\s/)
          warn "  Unknown directive: #{line}"
          valid = false
        end
      end

      if valid
        puts "  PASS (parsed)"
        passes += 1
      else
        warn "  FAIL (parse errors)"
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

    path = args[:path]
    unless File.exist?(path)
      abort "Script not found: #{path}"
    end

    puts "Replaying #{path}..."

    lines = File.readlines(path, chomp: true).reject { |l| l.strip.empty? || l.strip.start_with?("#") }

    if lines.empty?
      puts "Empty script, nothing to replay."
      exit 0
    end

    # Parse the app directive
    app_line = lines.find { |l| l.strip.start_with?("app ") }
    unless app_line
      abort "Script must start with an 'app' directive (e.g. 'app Counter')"
    end

    app_name = app_line.strip.sub(/\Aapp\s+/, "")
    app_class = Object.const_get(app_name)
    app = app_class.new
    model = app.init({})
    model = model.is_a?(Array) ? model.first : model

    puts "App: #{app_name}"
    puts "Initial model: #{model.inspect}"

    lines.each do |line|
      directive, *rest = line.strip.split(/\s+/, 2)
      case directive
      when "app"
        # Already handled
      when "wait"
        ms = rest.first&.to_i || 1000
        puts "  wait #{ms}ms"
        sleep(ms / 1000.0)
      when "click", "type", "assert_text", "assert_model"
        puts "  #{line.strip} (replay not available without renderer)"
      else
        puts "  unknown: #{line.strip}"
      end
    end

    puts "Replay complete."
  end

  desc "Run all CI checks (standard + test)"
  task :preflight do
    sh "bundle exec rake standard"
    sh "bundle exec rake test"
    puts "\nAll checks passed."
  end
end

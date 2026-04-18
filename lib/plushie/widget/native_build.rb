# frozen_string_literal: true

require "fileutils"
require "pathname"

module Plushie
  module Widget
    # Native widget build pipeline.
    #
    # Writes a virtual app crate under +_build/plushie-renderer-spec/+,
    # lists the configured native widget crates as path dependencies,
    # and delegates the actual workspace generation and `cargo build`
    # to +cargo plushie build+. The built binary is then copied into
    # +_build/plushie/bin/+ where the renderer discovery chain expects
    # to find it.
    #
    # All of the heavy lifting (workspace generation, [patch.crates-io]
    # forwarding, version-skew detection, collision checks, constructor
    # validation) lives in cargo-plushie so every host SDK shares one
    # implementation.
    module NativeBuild
      # Directory holding the generated virtual app crate that
      # cargo-plushie reads via cargo_metadata.
      SCRATCH_DIR = File.join("_build", "plushie-renderer-spec")

      module_function

      # Returns native widget classes from configuration.
      #
      # Reads from (in priority order):
      # 1. Plushie.configuration.widgets (set via Plushie.configure block)
      # 2. PLUSHIE_WIDGETS env var (comma-separated class names, for CI)
      #
      # Non-native widgets in the list are skipped with a warning.
      #
      # @return [Array<Class>] native widget classes
      def configured_widgets
        from_config = Plushie.configuration.widgets
        return filter_native(from_config) if from_config.is_a?(Array) && from_config.any?

        env = ENV["PLUSHIE_WIDGETS"] || ENV["PLUSHIE_EXTENSIONS"]
        return [] unless env && !env.strip.empty?

        names = env.split(",").map(&:strip).reject(&:empty?)
        classes = names.map do |name|
          Object.const_get(name)
        rescue NameError
          raise Error, "Widget class '#{name}' specified in PLUSHIE_WIDGETS could not be found. " \
            "Ensure the class is defined and the file is required before running the build."
        end
        filter_native(classes)
      end

      # Filter to native-only widgets, skipping non-native with a warning.
      #
      # @param classes [Array<Class>]
      # @return [Array<Class>]
      def filter_native(classes)
        classes.each { |mod| mod.finalize! if mod.respond_to?(:finalize!) }
        classes.select do |mod|
          if mod.respond_to?(:native?) && mod.native?
            true
          else
            warn "plushie: skipping #{mod.name} (not a native_widget)"
            false
          end
        end
      end

      # Resolve crate paths with directory traversal security check.
      #
      # Host SDKs are allowed to declare widget crates by relative
      # path. We refuse paths that escape the project root so a
      # malicious widget declaration can't point cargo at arbitrary
      # filesystem locations.
      #
      # @param widgets [Array<Class>] widget classes
      # @param base_dir [String] project root directory
      # @return [Hash{Class => String}] widget class to resolved absolute path
      def resolve_crate_paths(widgets, base_dir: Dir.pwd)
        widgets.each_with_object({}) do |mod, paths|
          rel = mod.native_crate
          resolved = File.expand_path(File.join(base_dir, rel))
          allowed = File.expand_path(base_dir)

          unless resolved.start_with?("#{allowed}/") || resolved == allowed
            raise Error, "Widget #{mod.name} native_crate path #{rel.inspect} " \
              "resolves to #{resolved}, which is outside the allowed directory #{allowed}"
          end

          paths[mod] = resolved
        end
      end

      # Build the renderer binary. Works for stock builds (no native
      # widgets) and custom builds (one or more native widgets).
      #
      # @param widgets [Array<Class>] native widget classes (may be empty)
      # @param release [Boolean] build with optimizations
      # @param verbose [Boolean] stream cargo-plushie output
      # @param bin_name [String, nil] override binary name
      # @return [String] path to the installed binary
      # @raise [Plushie::Error] on build failure
      def build_with_widgets(widgets, release: false, verbose: false, bin_name: nil, **_)
        bin_name ||= if widgets.empty?
          "plushie-renderer"
        else
          ENV["PLUSHIE_BUILD_NAME"] || Plushie.configuration.build_name
        end

        crate_paths = resolve_crate_paths(widgets)
        verify_widget_metadata!(crate_paths)

        scratch = File.expand_path(SCRATCH_DIR)
        FileUtils.mkdir_p(scratch)
        write_virtual_manifest(scratch, bin_name, crate_paths)

        puts "Widgets: #{widgets.map(&:name).join(", ")}" if widgets.any?

        invoke_cargo_plushie(scratch, release: release, verbose: verbose)

        binary_src = locate_built_binary(scratch, bin_name, release)
        unless File.exist?(binary_src)
          raise Error, "Build succeeded but binary not found at #{binary_src}"
        end

        install_binary(binary_src)
      end

      # Absolute path to the virtual app manifest we hand cargo-plushie.
      #
      # @param scratch [String]
      # @return [String]
      def manifest_path(scratch)
        File.join(scratch, "Cargo.toml")
      end

      # Verify each widget crate declares the metadata table
      # cargo-plushie looks for. cargo-plushie will also complain, but
      # failing here produces a message that references the Ruby
      # widget class name (far more useful than a cargo_metadata dump).
      #
      # @param crate_paths [Hash{Class => String}]
      # @return [void]
      def verify_widget_metadata!(crate_paths)
        crate_paths.each do |mod, crate_path|
          unless File.directory?(crate_path)
            raise Error,
              "widget #{mod.name} crate directory not found at #{crate_path}. " \
              "Check the rust_crate path configuration."
          end

          toml_path = File.join(crate_path, "Cargo.toml")
          unless File.exist?(toml_path)
            raise Error,
              "widget #{mod.name} crate at #{crate_path} is missing Cargo.toml"
          end

          content = File.read(toml_path)
          next if widget_metadata?(content)

          raise Error,
            "widget #{mod.name} crate #{crate_path} is missing " \
            "[package.metadata.plushie.widget] { type_name, constructor }. " \
            "Add that table so cargo plushie build can discover the widget."
        end
      end

      # Cheap TOML sniffer that avoids pulling in a parser. Looks for
      # the +[package.metadata.plushie.widget]+ header plus the two
      # required keys somewhere after it.
      #
      # @param content [String]
      # @return [Boolean]
      def widget_metadata?(content)
        header = /^\[package\.metadata\.plushie\.widget\]/.match(content)
        return false unless header

        rest = content.byteslice(header.end(0), content.bytesize) || ""
        # Stop at the next section header so we only consider keys
        # inside the widget table.
        body = rest.split(/^\[/, 2).first || ""
        body.match?(/^\s*type_name\s*=/) && body.match?(/^\s*constructor\s*=/)
      end

      # Write the virtual app Cargo.toml. The app package has no source
      # code of its own; it exists so cargo-plushie's `cargo metadata`
      # walk finds the widget crates as direct dependencies and the
      # [package.metadata.plushie] table supplies the binary name.
      #
      # @param scratch [String]
      # @param bin_name [String]
      # @param crate_paths [Hash{Class => String}]
      # @return [void]
      def write_virtual_manifest(scratch, bin_name, crate_paths)
        package_name = bin_name.tr("-", "_")

        dep_lines = crate_paths.values.map do |path|
          name = File.basename(path)
          %(#{name} = { path = "#{path}" })
        end

        content = <<~TOML
          # Auto-generated by rake plushie:build. Do not edit.
          #
          # This virtual manifest exists only so `cargo plushie build`
          # can discover the native widget crates via cargo_metadata.

          [package]
          name = "#{package_name}"
          version = "0.0.0"
          edition = "2024"
          publish = false

          [lib]
          path = "src/lib.rs"

          [dependencies]
          #{dep_lines.join("\n")}

          [package.metadata.plushie]
          binary_name = "#{bin_name}"
        TOML

        FileUtils.mkdir_p(File.join(scratch, "src"))
        File.write(File.join(scratch, "src", "lib.rs"), "")
        File.write(manifest_path(scratch), content)
      end

      # Shell out to cargo-plushie, passing the scratch manifest path.
      #
      # @param scratch [String]
      # @param release [Boolean]
      # @param verbose [Boolean]
      # @return [void]
      # @raise [Plushie::Error] on non-zero exit
      def invoke_cargo_plushie(scratch, release:, verbose:)
        program, preamble = Plushie::CargoPlushie.resolve
        args = preamble + ["build", "--manifest-path", manifest_path(scratch)]
        args << "--release" if release
        args << "--verbose" if verbose

        puts "Running: #{program} #{args.join(" ")}" if verbose
        ok = system(program, *args)
        return if ok

        raise Error, "cargo plushie build failed"
      end

      # Find the binary cargo-plushie produced. cargo-plushie writes
      # the generated renderer workspace under +<target>/plushie-renderer/+
      # and builds into that workspace's own +target/+. With the app
      # manifest at +<scratch>/Cargo.toml+, +<target>+ is
      # +<scratch>/target/+ unless +CARGO_TARGET_DIR+ is set.
      #
      # @param scratch [String]
      # @param bin_name [String]
      # @param release [Boolean]
      # @return [String]
      def locate_built_binary(scratch, bin_name, release)
        target_root = ENV["CARGO_TARGET_DIR"] || File.join(scratch, "target")
        profile = release ? "release" : "debug"
        ext = Gem.win_platform? ? ".exe" : ""
        File.join(target_root, "plushie-renderer", "target", profile, "#{bin_name}#{ext}")
      end

      # Install the built binary under +_build/plushie/bin/+ using the
      # platform-suffixed name so the renderer discovery chain finds it.
      #
      # @param src [String]
      # @return [String]
      def install_binary(src)
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
        dest
      end

      # Remove the build workspace and compiled artifacts.
      def clean!
        removed = false
        [File.join("_build", "plushie"), SCRATCH_DIR].each do |dir|
          next unless File.directory?(dir)
          FileUtils.rm_rf(dir)
          puts "Removed #{dir}"
          removed = true
        end
        puts "Nothing to clean" unless removed
      end
    end
  end
end

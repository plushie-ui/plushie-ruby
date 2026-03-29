# frozen_string_literal: true

require "fileutils"
require "pathname"

module Plushie
  module Widget
    # Build pipeline for the plushie renderer binary.
    #
    # Generates a Cargo workspace and builds a renderer binary. Works in
    # two modes:
    #
    # - **Stock build**: no native widgets. Generates a minimal workspace
    #   that depends on plushie-renderer from crates.io (or local source
    #   if PLUSHIE_SOURCE_PATH is set).
    # - **Custom build**: with native widgets. Each widget's Rust crate is
    #   included in the workspace and registered in the generated main.rs.
    #
    # Source checkout is optional. Without PLUSHIE_SOURCE_PATH, dependencies
    # are pulled from crates.io using BINARY_VERSION.
    module NativeBuild
      # Matches Rust constructor expressions including turbofish generics.
      # Valid: MyExt::new(), sparkline::Ext::<Config>::new(), create()
      # @api private
      RUST_CONSTRUCTOR_PATTERN = /\A[A-Za-z_][A-Za-z0-9_:<>, ]*(\([^)]*\))?\z/

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
        # Priority 1: Plushie.configure block
        from_config = Plushie.configuration.widgets
        if from_config.is_a?(Array) && from_config.any?
          return filter_native(from_config)
        end

        # Priority 2: env var (for CI / one-off builds)
        env = ENV["PLUSHIE_WIDGETS"] || ENV["PLUSHIE_EXTENSIONS"]
        return [] unless env && !env.strip.empty?

        names = env.split(",").map(&:strip).reject(&:empty?)
        classes = names.map { |name|
          begin
            Object.const_get(name)
          rescue NameError
            raise Error, "Widget class '#{name}' specified in PLUSHIE_WIDGETS could not be found. " \
              "Ensure the class is defined and the file is required before running the build."
          end
        }
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

      # Validate no type name collisions between widgets.
      #
      # @param widgets [Array<Class>] widget classes
      # @raise [Plushie::Error] if any two widgets claim the same type name
      # @return [void]
      def check_collisions!(widgets)
        all_types = widgets.flat_map { |mod| mod.type_names.map { |t| [t, mod] } }
        grouped = all_types.group_by(&:first)
        dupes = grouped.select { |_, v| v.length > 1 }

        return if dupes.empty?

        msgs = dupes.map { |type, entries|
          "  #{type}: #{entries.map { |_, m| m.name }.join(", ")}"
        }
        raise Error, "Widget type name collision detected:\n#{msgs.join("\n")}\n\n" \
          "Each type name must be handled by exactly one widget."
      end

      # Validate no crate name collisions between widgets.
      #
      # @param widgets [Array<Class>] widget classes with native_crate set
      # @raise [Plushie::Error] if any two widgets produce the same crate basename
      # @return [void]
      def check_crate_name_collisions!(widgets)
        crates = widgets.map { |mod| [File.basename(mod.native_crate), mod] }
        grouped = crates.group_by(&:first)
        dupes = grouped.select { |_, v| v.length > 1 }

        return if dupes.empty?

        msgs = dupes.map { |name, entries|
          "  #{name}: #{entries.map { |_, m| m.name }.join(", ")}"
        }
        raise Error, "Widget crate name collision detected:\n#{msgs.join("\n")}\n\n" \
          "Each widget's native_crate path must have a unique basename.\n" \
          "Rename one of the crate directories to resolve the conflict."
      end

      # Resolve crate paths with directory traversal security check.
      #
      # @param widgets [Array<Class>] widget classes
      # @param base_dir [String] project root directory
      # @return [Hash{Class => String}] map of widget class to resolved absolute path
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

      # Validate a Rust constructor expression is safe for codegen.
      # Allows identifiers, paths (::), turbofish generics (<>), and
      # simple invocations (parentheses).
      #
      # @param mod [Class] the widget class (for error messages)
      # @param constructor [String] the Rust expression
      def validate_rust_constructor!(mod, constructor)
        return if constructor.match?(RUST_CONSTRUCTOR_PATTERN)

        raise Error, "Widget #{mod.name} rust_constructor #{constructor.inspect} " \
          "contains invalid characters. Expected a Rust identifier, path (::), " \
          "or simple invocation (e.g. \"MyWidget::new()\" or \"MyWidget::<Config>::new()\")"
      end

      # Check that native widget crates depend on a compatible plushie-ext
      # version. Reads each crate's Cargo.toml and compares against
      # BINARY_VERSION. Warns on mismatch to prevent confusing Cargo errors.
      #
      # @param crate_paths [Hash{Class => String}]
      # @return [void]
      def check_widget_versions!(crate_paths)
        expected = Plushie::BINARY_VERSION
        expected_parts = expected.split(".").map(&:to_i)

        crate_paths.each do |mod, crate_path|
          cargo_toml = File.join(crate_path, "Cargo.toml")
          next unless File.exist?(cargo_toml)

          content = File.read(cargo_toml)
          dep_version = extract_plushie_ext_version(content, crate_path)
          next unless dep_version

          # Strip leading operators (^, ~, >=, =)
          base = dep_version.gsub(/\A[^0-9]*/, "")
          dep_parts = base.split(".").map(&:to_i)

          # Pre-1.0: major AND minor must match. 1.0+: major must match.
          compatible = if expected_parts[0] == 0
            dep_parts[0] == expected_parts[0] && dep_parts[1] == expected_parts[1]
          else
            dep_parts[0] == expected_parts[0]
          end

          unless compatible
            warn "plushie: widget #{mod.name} depends on plushie-ext #{dep_version}, " \
              "but this project targets #{expected}. " \
              "Update the widget's Rust crate to a compatible version."
          end
        end
      end

      # Generate the Cargo.toml content for the workspace.
      #
      # When source_path is set, uses local path dependencies and adds a
      # [patch.crates-io] section so widget crates that depend on plushie-ext
      # from crates.io get redirected to the same local checkout.
      #
      # When source_path is not set, uses crates.io version dependencies.
      def generate_cargo_toml(build_dir, bin_name, widgets, crate_paths)
        source_path = ENV["PLUSHIE_SOURCE_PATH"] || Plushie.configuration.source_path

        core_dep, bin_dep, patch_section = if source_path && File.directory?(source_path)
          core_rel = relative_path(File.join(source_path, "plushie-ext"), build_dir)
          bin_rel = relative_path(File.join(source_path, "plushie-renderer"), build_dir)

          # Patch section redirects crates.io deps to local source so
          # widget crates that depend on plushie-ext from crates.io get
          # the same local checkout. Without this, Cargo treats them as
          # different crates and trait impls don't match.
          ext_abs = File.expand_path(File.join(source_path, "plushie-ext"))
          renderer_abs = File.expand_path(File.join(source_path, "plushie-renderer"))

          patch = <<~TOML

            [patch.crates-io]
            plushie-ext = { path = "#{ext_abs}" }
            plushie-renderer = { path = "#{renderer_abs}" }
          TOML

          [%(plushie-ext = { path = "#{core_rel}" }),
            %(plushie-renderer = { path = "#{bin_rel}" }),
            patch]
        else
          version = Plushie::BINARY_VERSION
          [%(plushie-ext = "#{version}"),
            %(plushie-renderer = "#{version}"),
            ""]
        end

        ext_deps = widgets.map { |mod|
          path = crate_paths[mod]
          rel = relative_path(path, build_dir)
          name = File.basename(path)
          %(#{name} = { path = "#{rel}" })
        }.join("\n")

        package_name = bin_name.tr("-", "_")

        <<~TOML
          [package]
          name = "#{package_name}"
          version = "#{Plushie::VERSION}"
          edition = "2024"

          [[bin]]
          name = "#{bin_name}"
          path = "src/main.rs"

          [dependencies]
          #{core_dep}
          #{bin_dep}
          #{ext_deps}
          #{patch_section}
        TOML
      end

      # Generate main.rs with widget registrations.
      def generate_main_rs(widgets)
        builder_expr = if widgets.empty?
          "PlushieAppBuilder::new()"
        else
          registrations = widgets.map { |mod|
            constructor = mod.rust_constructor_expr
            validate_rust_constructor!(mod, constructor)
            "        .extension(#{constructor})"
          }.join("\n")
          "PlushieAppBuilder::new()\n#{registrations}"
        end

        <<~RUST
          // Auto-generated by rake plushie:build
          // Do not edit manually.

          use plushie_ext::app::PlushieAppBuilder;

          fn main() -> plushie_ext::iced::Result {
              let builder = #{builder_expr};
              plushie_renderer::run(builder)
          }
        RUST
      end

      # Build the renderer binary. Works for both stock builds (no native
      # widgets) and custom builds (with native widgets).
      #
      # @param widgets [Array<Class>] native widget classes (may be empty)
      # @param release [Boolean] build with optimizations
      # @param verbose [Boolean] print cargo output on success
      # @param bin_name [String, nil] override binary name
      # @return [String] path to the installed binary
      # @raise [Plushie::Error] on build failure
      def build_with_widgets(widgets, release: false, verbose: false, bin_name: nil)
        build_dir = File.join("_build", "plushie", "workspace")
        FileUtils.mkdir_p(build_dir)

        bin_name ||= if widgets.empty?
          "plushie-renderer"
        else
          ENV["PLUSHIE_BUILD_NAME"] || Plushie.configuration.build_name
        end

        crate_paths = resolve_crate_paths(widgets)

        if widgets.any?
          check_collisions!(widgets)
          check_crate_name_collisions!(widgets)
          check_widget_versions!(crate_paths)
        end

        generate_workspace(build_dir, bin_name, widgets, crate_paths)

        source_path = ENV["PLUSHIE_SOURCE_PATH"] || Plushie.configuration.source_path
        source_info = if source_path && File.directory?(source_path)
          "local source"
        else
          "crates.io v#{Plushie::BINARY_VERSION}"
        end

        puts "Source: #{source_info}"
        if widgets.any?
          puts "Widgets: #{widgets.map(&:name).join(", ")}"
        end

        release_flags = release ? ["--release"] : []
        profile = release ? "release" : "debug"

        label = release ? " (release)" : ""
        puts "Building #{bin_name}#{label}..."

        unless system("cargo", "build", *release_flags, chdir: build_dir)
          raise Error, "cargo build failed"
        end

        puts "Build succeeded."

        binary_src = File.join(build_dir, "target", profile, bin_name)
        unless File.exist?(binary_src)
          raise Error, "Build succeeded but binary not found at #{binary_src}"
        end

        install_binary(binary_src)
      end

      # Generate a Cargo workspace.
      # @api private
      def generate_workspace(build_dir, bin_name, widgets, crate_paths)
        cargo = generate_cargo_toml(build_dir, bin_name, widgets, crate_paths)
        File.write(File.join(build_dir, "Cargo.toml"), cargo)

        src_dir = File.join(build_dir, "src")
        FileUtils.mkdir_p(src_dir)
        main = generate_main_rs(widgets)
        File.write(File.join(src_dir, "main.rs"), main)
      end

      # Install the built binary.
      # @api private
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

      # Compute a relative path between two directories.
      # @api private
      def relative_path(target, from)
        Pathname.new(File.expand_path(target))
          .relative_path_from(Pathname.new(File.expand_path(from))).to_s
      end

      # Extract plushie-ext version from a Cargo.toml content string.
      # @api private
      def extract_plushie_ext_version(content, crate_path)
        # Inline: plushie-ext = "0.5.0"
        if (match = content.match(/plushie-ext\s*=\s*"([^"]+)"/))
          return match[1]
        end

        # Table with version: plushie-ext = { version = "0.5.0", ... }
        if (match = content.match(/plushie-ext\s*=\s*\{[^}]*version\s*=\s*"([^"]+)"/))
          return match[1]
        end

        # Table with path: plushie-ext = { path = "..." }
        if (match = content.match(/plushie-ext\s*=\s*\{[^}]*path\s*=\s*"([^"]+)"/))
          target_toml = File.join(File.expand_path(match[1], crate_path), "Cargo.toml")
          if File.exist?(target_toml)
            pkg_content = File.read(target_toml)
            if (pkg_match = pkg_content.match(/\[package\][^\[]*version\s*=\s*"([^"]+)"/m))
              return pkg_match[1]
            end
          end
        end

        nil
      end
    end
  end
end

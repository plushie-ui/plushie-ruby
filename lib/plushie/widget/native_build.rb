# frozen_string_literal: true

require "fileutils"
require "pathname"

module Plushie
  module Widget
    # Build pipeline for native Rust widgets.
    #
    # Generates a custom Cargo workspace that registers each widget's
    # crate and builds a combined binary.
    module NativeBuild
      # Template for generated Rust constructor code.
      # @api private
      RUST_CONSTRUCTOR_PATTERN = /\A[A-Za-z_][A-Za-z0-9_:]*(\([^)]*\))?\z/

      module_function

      # Returns native widget classes from configuration.
      #
      # Reads from (in priority order):
      # 1. Plushie.configuration.widgets (set via Plushie.configure block)
      # 2. PLUSHIE_WIDGETS env var (comma-separated class names, for CI)
      #
      # @return [Array<Class>] native widget classes
      def configured_widgets
        # Priority 1: Plushie.configure block
        from_config = Plushie.configuration.widgets
        if from_config.is_a?(Array) && from_config.any?
          return validate_widgets(from_config)
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
        validate_widgets(classes)
      end

      # Validate that each class is a native widget.
      #
      # @param classes [Array<Class>]
      # @return [Array<Class>]
      def validate_widgets(classes)
        classes.each do |mod|
          mod.finalize! if mod.respond_to?(:finalize!)
          unless mod.respond_to?(:native?) && mod.native?
            raise Error, "#{mod.name} is configured as a widget but is not a native_widget"
          end
        end
        classes
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
      #
      # @param mod [Class] the widget class (for error messages)
      # @param constructor [String] the Rust expression
      def validate_rust_constructor!(mod, constructor)
        return if constructor.match?(RUST_CONSTRUCTOR_PATTERN)

        raise Error, "Widget #{mod.name} rust_constructor #{constructor.inspect} " \
          "contains invalid characters. Expected a Rust identifier, path (::), " \
          "or simple invocation (e.g. \"MyWidget::new()\")"
      end

      # Generate the Cargo.toml content for the custom workspace.
      def generate_cargo_toml(build_dir, bin_name, widgets, crate_paths)
        source_path = ENV["PLUSHIE_SOURCE_PATH"] || Plushie.configuration.source_path

        core_dep, bin_dep = if source_path && File.directory?(source_path)
          core_rel = relative_path(File.join(source_path, "plushie-ext"), build_dir)
          bin_rel = relative_path(File.join(source_path, "plushie-renderer"), build_dir)
          [%(plushie-ext = { path = "#{core_rel}" }),
            %(plushie-renderer = { path = "#{bin_rel}" })]
        else
          version = Plushie::BINARY_VERSION
          [%(plushie-ext = "#{version}"),
            %(plushie-renderer = "#{version}")]
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
        TOML
      end

      # Generate main.rs with widget registrations.
      def generate_main_rs(widgets)
        registrations = widgets.map { |mod|
          constructor = mod.rust_constructor_expr
          validate_rust_constructor!(mod, constructor)
          "        .extension(#{constructor})"
        }.join("\n")

        <<~RUST
          // Auto-generated by rake plushie:build
          // Do not edit manually.

          use plushie_ext::app::PlushieAppBuilder;
          use plushie_ext::iced;

          fn main() -> iced::Result {
              let builder = PlushieAppBuilder::new()
          #{registrations};
              plushie_renderer::run(builder)
          }
        RUST
      end

      # Generate the workspace and build the custom binary.
      def build_with_widgets(widgets, release: false, verbose: false)
        build_dir = File.join("_build", "plushie", "custom")
        FileUtils.mkdir_p(build_dir)

        bin_name = ENV["PLUSHIE_BUILD_NAME"] || Plushie.configuration.build_name
        crate_paths = resolve_crate_paths(widgets)

        check_collisions!(widgets)
        check_crate_name_collisions!(widgets)

        generate_workspace(build_dir, bin_name, widgets, crate_paths)

        widget_names = widgets.map(&:name).join(", ")
        puts "Generated custom build workspace at #{build_dir} " \
          "with widgets: #{widget_names}"

        release_flags = release ? ["--release"] : []
        profile = release ? "release" : "debug"

        label = release ? " (release)" : ""
        puts "Building #{bin_name}#{label}..."

        unless system("cargo", "build", *release_flags, chdir: build_dir)
          raise Error, "cargo build failed for custom build workspace"
        end

        puts "Build succeeded."

        binary_src = File.join(build_dir, "target", profile, bin_name)
        unless File.exist?(binary_src)
          raise Error, "Build succeeded but binary not found at #{binary_src}"
        end

        install_binary(binary_src)
      end

      # Generate a Cargo workspace for widget builds.
      # @api private
      def generate_workspace(build_dir, bin_name, widgets, crate_paths)
        cargo = generate_cargo_toml(build_dir, bin_name, widgets, crate_paths)
        File.write(File.join(build_dir, "Cargo.toml"), cargo)

        src_dir = File.join(build_dir, "src")
        FileUtils.mkdir_p(src_dir)
        main = generate_main_rs(widgets)
        File.write(File.join(src_dir, "main.rs"), main)
      end

      # Install the built widget binary.
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
    end
  end
end

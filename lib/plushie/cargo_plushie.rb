# frozen_string_literal: true

require "open3"

module Plushie
  # Resolves the command that invokes cargo-plushie.
  #
  # The native widget build pipeline shells out to cargo-plushie to
  # generate the renderer workspace and drive `cargo build`. This
  # module decides *how* that shell-out happens:
  #
  # 1. If +PLUSHIE_RUST_SOURCE_PATH+ points at a plushie-rust checkout,
  #    run the workspace copy with +cargo run -p cargo-plushie+. This
  #    is the dev path (no install required, always matches the
  #    checkout).
  # 2. Otherwise, if a +cargo-plushie+ binary is on +PATH+ and its
  #    +--version+ matches +PLUSHIE_RUST_VERSION+, use it directly.
  # 3. Otherwise, raise with guidance on how to install the matching
  #    version.
  module CargoPlushie
    module_function

    # Resolve an executable command for invoking cargo-plushie.
    #
    # Returns a tuple +[program, preamble_args]+ that the caller uses
    # to build a shell command: +[program, *preamble_args, *user_args]+.
    #
    # @return [Array(String, Array<String>)]
    # @raise [Plushie::Error] when no usable cargo-plushie is available
    def resolve
      if (source = source_path) && File.directory?(source)
        return resolve_via_source(source)
      end

      case check_path_version
      when :match
        ["cargo-plushie", []]
      when :mismatch
        raise Error, mismatch_message
      when :missing
        raise Error, missing_message
      end
    end

    # Exposed for testing. In production, reads
    # +PLUSHIE_RUST_SOURCE_PATH+ first, falling back to
    # +Plushie.configuration.source_path+.
    #
    # @return [String, nil]
    def source_path
      ENV["PLUSHIE_RUST_SOURCE_PATH"] || Plushie.configuration.source_path
    end

    # @param source [String] plushie-rust checkout root
    # @return [Array(String, Array<String>)]
    def resolve_via_source(source)
      manifest = File.join(source, "Cargo.toml")
      ["cargo",
        ["run", "--manifest-path", manifest,
          "-p", "cargo-plushie",
          "--release", "--quiet", "--"]]
    end

    # Probe +cargo-plushie --version+ and compare against
    # +PLUSHIE_RUST_VERSION+.
    #
    # @return [:match, :mismatch, :missing]
    def check_path_version
      stdout, _stderr, status = Open3.capture3("cargo-plushie", "--version")
    rescue Errno::ENOENT
      :missing
    else
      return :missing unless status.success?

      installed = extract_version(stdout)
      return :missing unless installed

      (installed == Plushie::PLUSHIE_RUST_VERSION) ? :match : :mismatch
    end

    # Pull the version token out of a +cargo-plushie --version+ line.
    # Typical output: +"cargo-plushie 0.6.1\n"+.
    #
    # @param output [String]
    # @return [String, nil]
    def extract_version(output)
      output.to_s.split(/\s+/).find do |token|
        token.match?(/\A\d+\.\d+\.\d+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\z/) ||
          token.match?(/\A\d+\.\d+\.\d+(?:\+[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?\z/)
      end
    end

    # @return [String]
    def mismatch_message
      expected = Plushie::PLUSHIE_RUST_VERSION
      <<~MSG.chomp
        cargo-plushie on PATH is not version #{expected}.

        Install the matching version:
          cargo install cargo-plushie --version #{expected} --locked

        Or point at a plushie-rust checkout:
          export PLUSHIE_RUST_SOURCE_PATH=/path/to/plushie-rust
      MSG
    end

    # @return [String]
    def missing_message
      expected = Plushie::PLUSHIE_RUST_VERSION
      <<~MSG.chomp
        cargo-plushie not found on PATH.

        Install it:
          cargo install cargo-plushie --version #{expected} --locked

        Or point at a plushie-rust checkout:
          export PLUSHIE_RUST_SOURCE_PATH=/path/to/plushie-rust
      MSG
    end
  end
end

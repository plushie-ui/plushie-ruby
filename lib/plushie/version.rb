# frozen_string_literal: true

module Plushie
  # Current version of the plushie gem.
  VERSION = "0.5.0"

  # The plushie-rust release this SDK targets. Host SDKs pin to this
  # exact version to download the matching renderer binary, install the
  # matching cargo-plushie, and emit matching dep versions into
  # generated Cargo.toml. See plushie-rust docs/versioning.md.
  PLUSHIE_RUST_VERSION = "0.6.1"
end

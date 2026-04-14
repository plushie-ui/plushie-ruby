# Steepfile
#
# Files listed here are type-checked against their RBS declarations.
# Files with heavy metaprogramming (widget.rb define_method closures,
# Widget.define class_eval blocks) are excluded because Steep cannot
# analyze their dynamic method generation.
target :lib do
  signature "sig"

  # Core modules
  check "lib/plushie/app.rb"
  check "lib/plushie/encode.rb"
  check "lib/plushie/event/specs.rb"
  check "lib/plushie/key_modifiers.rb"
  check "lib/plushie/route.rb"
  check "lib/plushie/selection.rb"
  check "lib/plushie/undo.rb"
  check "lib/plushie/version.rb"

  # Excluded from checking (RBS declarations retained for consumers):
  #
  # - model.rb: Extensions#with is defined inside a Data.define block;
  #   Steep resolves `self` to the enclosing module, not the Data class.
  # - node.rb: Node = Data.define block; same self-resolution issue.
  # - subscription.rb: Sub = Data.define block; same self-resolution issue.
  # - event.rb: Widget/Key/Ime/Window/Modifiers/CommandError/System are
  #   all Data.define with block overrides; same self-resolution issue.

  # Tree (normalization, search, diff)
  check "lib/plushie/tree.rb"
  check "lib/plushie/tree/search.rb"
  check "lib/plushie/tree/diff.rb"

  # Protocol (decode is the most type-critical)
  check "lib/plushie/protocol.rb"
  check "lib/plushie/protocol/decode.rb"

  # Runtime
  check "lib/plushie/runtime.rb"
  check "lib/plushie/runtime/commands.rb"
  check "lib/plushie/animation.rb"

  # Widget build helpers
  check "lib/plushie/widget/build.rb"

  # Type modules
  check "lib/plushie/type/line_height.rb"

  library "json"
  library "logger"
  library "securerandom"
end

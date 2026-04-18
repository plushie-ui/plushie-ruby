# frozen_string_literal: true

require "test_helper"

class TestVersion < Minitest::Test
  def test_has_a_version_number
    refute_nil Plushie::VERSION
  end

  def test_has_a_plushie_rust_version
    refute_nil Plushie::PLUSHIE_RUST_VERSION
  end
end

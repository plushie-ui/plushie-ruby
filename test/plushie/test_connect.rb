# frozen_string_literal: true

require "test_helper"

class TestConnect < Minitest::Test
  class App
  end

  def test_connect_spawns_renderer_without_socket
    calls = []

    Plushie.stub(:run, ->(app_class, **opts) {
      calls << [app_class, opts]
    }) do
      Plushie.connect(App, socket: nil, token: "secret", format: :json)
    end

    assert_equal [[App, {token: "secret", format: :json}]], calls
  end

  def test_connect_uses_socket_when_present
    adapter = Object.new
    calls = []

    Plushie::Transport::SocketAdapter.stub(:connect, ->(socket) {
      assert_equal "/tmp/plushie.sock", socket
      adapter
    }) do
      Plushie.stub(:run, ->(app_class, **opts) {
        calls << [app_class, opts]
      }) do
        Plushie.connect(
          App,
          socket: "/tmp/plushie.sock",
          token: "secret",
          format: :msgpack
        )
      end
    end

    assert_equal(
      [[App, {transport: [:iostream, adapter], token: "secret", format: :msgpack}]],
      calls
    )
  end
end

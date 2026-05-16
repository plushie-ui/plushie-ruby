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

  # Token precedence: explicit arg wins over env and stdin.
  def test_connect_explicit_token_wins_over_env_and_stdin
    adapter = Object.new
    calls = []
    stdin_read = false

    Plushie.stub(:read_token_from_stdin, -> {
      stdin_read = true
      "stdin-token"
    }) do
      Plushie::Transport::SocketAdapter.stub(:connect, ->(_socket) { adapter }) do
        Plushie.stub(:run, ->(app_class, **opts) { calls << [app_class, opts] }) do
          Plushie.connect(App, socket: "/tmp/plushie.sock", token: "explicit")
        end
      end
    end

    assert_equal "explicit", calls.first&.last&.fetch(:token)
    refute stdin_read, "stdin should not be read when explicit token given"
  end

  # Token precedence: env wins over stdin.
  def test_connect_env_token_wins_over_stdin
    adapter = Object.new
    calls = []
    stdin_read = false

    old_env = ENV.delete("PLUSHIE_TOKEN")
    ENV["PLUSHIE_TOKEN"] = "env-token"

    Plushie.stub(:read_token_from_stdin, -> {
      stdin_read = true
      "stdin-token"
    }) do
      Plushie::Transport::SocketAdapter.stub(:connect, ->(_socket) { adapter }) do
        Plushie.stub(:run, ->(app_class, **opts) { calls << [app_class, opts] }) do
          Plushie.connect(App, socket: "/tmp/plushie.sock")
        end
      end
    end

    assert_equal "env-token", calls.first&.last&.fetch(:token)
    refute stdin_read, "stdin should not be read when PLUSHIE_TOKEN is set"
  ensure
    if old_env
      ENV["PLUSHIE_TOKEN"] = old_env
    else
      ENV.delete("PLUSHIE_TOKEN")
    end
  end

  # Token precedence: stdin used when neither arg nor env is set.
  def test_connect_reads_token_from_stdin_when_no_arg_or_env
    adapter = Object.new
    calls = []

    old_env = ENV.delete("PLUSHIE_TOKEN")

    Plushie.stub(:read_token_from_stdin, -> { "stdin-token" }) do
      Plushie::Transport::SocketAdapter.stub(:connect, ->(_socket) { adapter }) do
        Plushie.stub(:run, ->(app_class, **opts) { calls << [app_class, opts] }) do
          Plushie.connect(App, socket: "/tmp/plushie.sock", token: nil)
        end
      end
    end

    assert_equal "stdin-token", calls.first&.last&.fetch(:token)
  ensure
    if old_env
      ENV["PLUSHIE_TOKEN"] = old_env
    else
      ENV.delete("PLUSHIE_TOKEN")
    end
  end

  # Error on stdin timeout: raises with clear message.
  def test_connect_raises_on_stdin_timeout
    old_env = ENV.delete("PLUSHIE_TOKEN")

    Plushie.stub(:read_token_from_stdin, -> {}) do
      err = assert_raises(Plushie::Error) do
        Plushie.connect(App, socket: "/tmp/plushie.sock", token: nil)
      end
      assert_includes err.message, "renderer-parent token not provided"
      assert_includes err.message, "PLUSHIE_TOKEN"
    end
  ensure
    if old_env
      ENV["PLUSHIE_TOKEN"] = old_env
    else
      ENV.delete("PLUSHIE_TOKEN")
    end
  end

  # read_token_from_stdin: returns nil on timeout (IO.select returns nil).
  def test_read_token_from_stdin_returns_nil_on_timeout
    IO.stub(:select, ->(*_args) {}) do
      result = Plushie.read_token_from_stdin(timeout: 0.001)
      assert_nil result
    end
  end

  # read_token_from_stdin: parses valid JSON token line.
  def test_read_token_from_stdin_parses_valid_json
    fake_stdin = StringIO.new(%({"token":"abc123"}\n))

    IO.stub(:select, ->(*_args) { [[$stdin]] }) do
      $stdin.stub(:gets, -> { fake_stdin.gets }) do
        result = Plushie.read_token_from_stdin(timeout: 1.0)
        assert_equal "abc123", result
      end
    end
  end

  # read_token_from_stdin: raises on invalid JSON.
  def test_read_token_from_stdin_raises_on_invalid_json
    IO.stub(:select, ->(*_args) { [[$stdin]] }) do
      $stdin.stub(:gets, -> { "not-json\n" }) do
        err = assert_raises(Plushie::Error) do
          Plushie.read_token_from_stdin(timeout: 1.0)
        end
        assert_includes err.message, "renderer-parent token stdin must be JSON object with 'token' string"
      end
    end
  end

  # read_token_from_stdin: raises when JSON object lacks "token" string.
  def test_read_token_from_stdin_raises_on_wrong_shape
    IO.stub(:select, ->(*_args) { [[$stdin]] }) do
      $stdin.stub(:gets, -> { %({"other":"value"}\n) }) do
        err = assert_raises(Plushie::Error) do
          Plushie.read_token_from_stdin(timeout: 1.0)
        end
        assert_includes err.message, "renderer-parent token stdin must be JSON object with 'token' string"
      end
    end
  end

  # read_token_from_stdin: raises when "token" value is not a string.
  def test_read_token_from_stdin_raises_when_token_not_string
    IO.stub(:select, ->(*_args) { [[$stdin]] }) do
      $stdin.stub(:gets, -> { %({"token":42}\n) }) do
        err = assert_raises(Plushie::Error) do
          Plushie.read_token_from_stdin(timeout: 1.0)
        end
        assert_includes err.message, "renderer-parent token stdin must be JSON object with 'token' string"
      end
    end
  end

  # read_token_from_stdin: returns nil when stdin is closed (gets returns nil).
  def test_read_token_from_stdin_returns_nil_on_closed_stdin
    IO.stub(:select, ->(*_args) { [[$stdin]] }) do
      $stdin.stub(:gets, -> {}) do
        result = Plushie.read_token_from_stdin(timeout: 1.0)
        assert_nil result
      end
    end
  end

  # read_token_from_stdin: returns nil on empty line.
  def test_read_token_from_stdin_returns_nil_on_empty_line
    IO.stub(:select, ->(*_args) { [[$stdin]] }) do
      $stdin.stub(:gets, -> { "\n" }) do
        result = Plushie.read_token_from_stdin(timeout: 1.0)
        assert_nil result
      end
    end
  end
end

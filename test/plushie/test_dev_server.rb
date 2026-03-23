# frozen_string_literal: true

require "test_helper"

class TestDevServer < Minitest::Test
  # -- Lifecycle: graceful degradation without listen gem -------------------

  def test_start_without_listen_gem_does_not_raise
    queue = Thread::Queue.new
    dev = Plushie::DevServer.new(event_queue: queue)

    # DevServer.start rescues LoadError when `listen` isn't available.
    # It should not raise or crash -- just log a warning and return.
    dev.start
    dev.stop

    # Queue should be empty since no file changes happened
    assert queue.empty?
  end

  def test_stop_is_idempotent
    queue = Thread::Queue.new
    dev = Plushie::DevServer.new(event_queue: queue)

    # Stopping without starting should be safe
    dev.stop
    dev.stop
  end

  # -- perform_reload pushes :force_rerender -------------------------------

  def test_perform_reload_pushes_force_rerender
    queue = Thread::Queue.new
    dev = Plushie::DevServer.new(event_queue: queue)

    # Create a temporary file so `load` has something real to process
    require "tempfile"
    tmp = Tempfile.new(["plushie_test", ".rb"])
    tmp.write("# noop\n")
    tmp.flush

    # Call the private perform_reload method directly
    dev.send(:perform_reload, [tmp.path])

    msg = queue.pop
    assert_equal :force_rerender, msg
  ensure
    tmp&.close
    tmp&.unlink
  end

  # -- perform_reload handles StandardError in individual files ------------

  def test_perform_reload_handles_runtime_errors_gracefully
    queue = Thread::Queue.new
    dev = Plushie::DevServer.new(event_queue: queue)

    # Create a file that raises a RuntimeError when loaded
    require "tempfile"
    tmp = Tempfile.new(["plushie_bad", ".rb"])
    tmp.write("raise 'intentional test error'\n")
    tmp.flush

    # Should not propagate the error
    dev.send(:perform_reload, [tmp.path])

    msg = queue.pop
    assert_equal :force_rerender, msg
  ensure
    tmp&.close
    tmp&.unlink
  end
end

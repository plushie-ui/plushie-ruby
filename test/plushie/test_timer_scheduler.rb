# frozen_string_literal: true

require "test_helper"

class TestTimerScheduler < Minitest::Test
  def test_stop_joins_scheduler_thread
    scheduler = Plushie::TimerScheduler.new
    thread = scheduler.instance_variable_get(:@thread)

    scheduler.stop

    thread.join(0.1)
    refute thread.alive?
  end

  def test_stop_is_idempotent
    scheduler = Plushie::TimerScheduler.new

    scheduler.stop
    scheduler.stop
  end

  def test_concurrent_stop_is_idempotent
    scheduler = Plushie::TimerScheduler.new

    threads = 2.times.map { Thread.new { scheduler.stop } }
    threads.each(&:join)
  end
end

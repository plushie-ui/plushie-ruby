# frozen_string_literal: true

require_relative "bounded_queue"

module Plushie
  # Single-thread timer scheduler for timer subscriptions.
  #
  # Replaces the per-timer Thread.new pattern with one thread that
  # manages all timers via IO.select with a deadline-based timeout.
  # Adding or cancelling a timer wakes the scheduler through a pipe
  # so it can recalculate the next deadline immediately.
  #
  # @example
  #   scheduler = TimerScheduler.new
  #   scheduler.schedule(tag: "tick", interval_ms: 1000, event_queue: queue)
  #   scheduler.cancel("tick")
  #   scheduler.stop
  class TimerScheduler
    def initialize
      @pipe_r, @pipe_w = IO.pipe
      @timers = {}
      @mutex = Mutex.new
      @thread = Thread.new { run_loop }
      @thread.name = "plushie-timer-scheduler"
    end

    def schedule(tag:, interval_ms:, event_queue:)
      interval = interval_ms / 1000.0
      @mutex.synchronize do
        @timers[tag] = {
          interval: interval,
          deadline: Process.clock_gettime(Process::CLOCK_MONOTONIC) + interval,
          queue: event_queue
        }
      end
      wake
    end

    def cancel(tag)
      @mutex.synchronize { @timers.delete(tag) }
      wake
    end

    def stop
      @thread&.kill
      @thread = nil
      @pipe_r&.close
      @pipe_w&.close
    end

    private

    def wake
      @pipe_w.write_nonblock(".")
    rescue IOError, Errno::EPIPE
      nil
    end

    def drain_pipe
      @pipe_r.read_nonblock(4096)
    rescue IOError, IO::EAGAINWaitReadable
      nil
    end

    def run_loop
      loop do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        next_deadline = nil

        timers_to_fire = []
        @mutex.synchronize do
          @timers.each do |tag, timer|
            if now >= timer[:deadline]
              timers_to_fire << [tag, timer[:queue]]
              timer[:deadline] = now + timer[:interval]
            end
            next_deadline = timer[:deadline] if next_deadline.nil? || timer[:deadline] < next_deadline
          end
        end

        timers_to_fire.each do |tag, queue|
          BoundedQueue.push(queue, [:timer_tick, tag])
        end

        drain_pipe

        timeout = next_deadline ? [next_deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0.001].max : 3600
        IO.select([@pipe_r], [], [], timeout)
      end
    rescue IOError
      # Pipe closed during shutdown
    end
  end
end

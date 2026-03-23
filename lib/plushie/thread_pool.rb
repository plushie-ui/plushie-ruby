# frozen_string_literal: true

require "etc"

module Plushie
  # Simple bounded thread pool for background work.
  #
  # Worker threads pull tasks from a shared queue. Sized to CPU count
  # by default. Used for non-cancellable background operations.
  #
  # Note: Command.async and Command.stream spawn dedicated threads
  # (not from this pool) because they need individual cancel handles.
  # The pool is used by the test framework and other non-cancellable work.
  #
  # @example
  #   pool = ThreadPool.new(size: 4)
  #   pool.post { expensive_work() }
  #   pool.shutdown
  #
  class ThreadPool
    # @return [Integer] number of worker threads
    attr_reader :size

    # Create a new thread pool.
    #
    # @param size [Integer, nil] number of workers (default: CPU count)
    def initialize(size: nil)
      @size = size || default_size
      @queue = Thread::Queue.new
      @shutdown = false
      @workers = @size.times.map { spawn_worker }
    end

    # Queue a block for execution by a worker thread.
    #
    # @yield the work to execute
    # @raise [RuntimeError] if the pool has been shut down
    def post(&block)
      raise "ThreadPool is shut down" if @shutdown
      @queue.push(block)
    end

    # Shut down the pool. Signals all workers to stop and waits
    # for them to finish current work.
    #
    # @param timeout [Numeric] max seconds to wait per worker (default: 5)
    def shutdown(timeout: 5)
      return if @shutdown
      @shutdown = true
      @size.times { @queue.push(:shutdown) }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      @workers.each do |t|
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        t.join([remaining, 0].max)
      end
    end

    # @return [Boolean] true if the pool has been shut down
    def shutdown?
      @shutdown
    end

    private

    def spawn_worker
      Thread.new do
        while (work = @queue.pop) != :shutdown
          begin
            work.call
          rescue => e
            # Worker exceptions are swallowed to keep the pool alive.
            # The caller is responsible for error handling in their block.
            warn "plushie: thread pool worker error: #{e.class}: #{e.message}" if $DEBUG
          end
        end
      end
    end

    def default_size
      Etc.respond_to?(:nprocessors) ? [Etc.nprocessors, 2].max : 4
    end
  end
end

# frozen_string_literal: true

module Plushie
  # Simple bounded thread pool for async command execution.
  #
  # Sized to CPU count by default. Posts work to a queue; worker
  # threads pull and execute. No external dependencies.
  #
  #   pool = ThreadPool.new(size: 4)
  #   pool.post { expensive_work() }
  #   pool.shutdown
  #
  class ThreadPool
    # TODO: implement
  end
end

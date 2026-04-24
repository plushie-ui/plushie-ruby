# frozen_string_literal: true

module Plushie
  # Small wrapper around SizedQueue for runtime mailboxes.
  module BoundedQueue
    EVENT_CAPACITY = 1024
    CONNECTION_CAPACITY = 1024
    SESSION_CAPACITY = 256

    module_function

    def new(capacity = EVENT_CAPACITY)
      SizedQueue.new(capacity)
    end

    def push(queue, item, timeout: nil)
      if timeout
        queue.push(item, false, timeout: timeout)
      else
        queue.push(item)
      end
    rescue ClosedQueueError
      nil
    end

    def try_push(queue, item)
      queue.push(item, true)
    rescue ClosedQueueError, ThreadError
      nil
    end
  end
end

# frozen_string_literal: true

require "test_helper"

class TestThreadPool < Minitest::Test
  def test_post_executes_work
    pool = Plushie::ThreadPool.new(size: 2)
    results = Thread::Queue.new

    pool.post { results.push(:done) }
    assert_equal :done, results.pop

    pool.shutdown
  end

  def test_multiple_posts
    pool = Plushie::ThreadPool.new(size: 2)
    results = Thread::Queue.new

    5.times { |i| pool.post { results.push(i) } }

    collected = 5.times.map { results.pop }
    assert_equal [0, 1, 2, 3, 4].sort, collected.sort

    pool.shutdown
  end

  def test_shutdown_joins_workers
    pool = Plushie::ThreadPool.new(size: 2)
    pool.post { sleep(0.01) }
    pool.shutdown
    assert pool.shutdown?
  end

  def test_post_after_shutdown_raises
    pool = Plushie::ThreadPool.new(size: 1)
    pool.shutdown
    assert_raises(RuntimeError) { pool.post { :noop } }
  end

  def test_worker_exceptions_dont_kill_pool
    pool = Plushie::ThreadPool.new(size: 1)
    results = Thread::Queue.new

    pool.post { raise "boom" }
    pool.post { results.push(:after_error) }

    assert_equal :after_error, results.pop
    pool.shutdown
  end

  def test_default_size
    pool = Plushie::ThreadPool.new
    assert pool.size >= 2
    pool.shutdown
  end
end

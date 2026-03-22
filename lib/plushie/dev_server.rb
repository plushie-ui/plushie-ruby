# frozen_string_literal: true

module Plushie
  # File watcher and hot-reloader for development mode.
  #
  # Watches lib/ (configurable) for .rb file changes, debounces rapid
  # saves, and triggers a re-render in the runtime. The model state is
  # preserved across reloads -- only the view is re-evaluated.
  #
  # Requires the `listen` gem (optional dependency, not in gemspec).
  # Install it in your Gemfile for development:
  #
  #   gem "listen", group: :development
  #
  # @example
  #   Plushie.run(MyApp, dev: true)
  #
  # @example Manual control
  #   dev = DevServer.new(event_queue: runtime_queue, dirs: ["lib/"])
  #   dev.start
  #   dev.stop
  #
  # @see ~/projects/toddy-elixir/lib/plushie/dev_server.ex
  class DevServer
    # @param event_queue [Thread::Queue] runtime event queue for :force_rerender
    # @param dirs [Array<String>] directories to watch (default: ["lib/"])
    # @param debounce_ms [Integer] debounce window in milliseconds (default: 100)
    def initialize(event_queue:, dirs: nil, debounce_ms: 100)
      @event_queue = event_queue
      @dirs = dirs || ["lib/"]
      @debounce_ms = debounce_ms
      @listener = nil
      @debounce_timer = nil
      @debounce_mutex = Mutex.new
      @logger = Logger.new($stderr, level: :info, progname: "plushie-dev")
    end

    # Start watching for file changes.
    def start
      begin
        require "listen"
      rescue LoadError
        @logger.warn("plushie dev: `listen` gem not found. Add it to your Gemfile for hot reload.")
        return
      end

      @listener = Listen.to(*@dirs, only: /\.rb$/) do |modified, added, _removed|
        files = (modified + added).uniq
        schedule_reload(files) unless files.empty?
      end

      @listener.start
      @logger.info("plushie dev: watching #{@dirs.join(", ")} for changes")
    end

    # Stop watching.
    def stop
      @listener&.stop
      @debounce_timer&.kill
      @listener = nil
    end

    private

    def schedule_reload(files)
      @debounce_mutex.synchronize do
        @debounce_timer&.kill
        @debounce_timer = Thread.new do
          sleep(@debounce_ms / 1000.0)
          perform_reload(files)
        end
      end
    end

    def perform_reload(files)
      files.each do |file|
        @logger.info("plushie dev: reloading #{file}")
        load(file)
      rescue => e
        @logger.error("plushie dev: error reloading #{file}: #{e.class}: #{e.message}")
      end

      @event_queue.push(:force_rerender)
    end
  end
end

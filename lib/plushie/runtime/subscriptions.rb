# frozen_string_literal: true

module Plushie
  class Runtime
    # Subscription lifecycle management for the Plushie runtime.
    #
    # Compares the app's subscribe(model) output against active
    # subscriptions, starting new ones and stopping removed ones.
    # Timer subscriptions run locally; renderer subscriptions are
    # forwarded to the bridge.
    #
    # @see ~/projects/toddy-elixir/lib/plushie/runtime/subscriptions.ex
    module Subscriptions
      private

      # Synchronize subscriptions with the app's current subscribe output.
      # Called after each update cycle.
      def sync_subscriptions
        new_specs = begin
          subs = @app.subscribe(@model)
          subs.is_a?(Array) ? subs : []
        rescue => e
          @logger.error("plushie: subscribe raised: #{e.class}: #{e.message}")
          []
        end

        new_by_key = new_specs.each_with_object({}) { |spec, h| h[spec.key] = spec }
        new_sorted_keys = new_by_key.keys.sort_by(&:to_s)

        if new_sorted_keys == @subscription_keys
          # Short-circuit: key set unchanged, just check max_rate updates
          update_max_rates(new_by_key)
        else
          diff_subscriptions(new_by_key, new_sorted_keys)
        end
      end

      # Full diff of subscription sets.
      def diff_subscriptions(new_by_key, new_sorted_keys)
        old_keys = @subscriptions.keys.to_set
        new_keys = new_by_key.keys.to_set

        # Stop removed subscriptions
        (old_keys - new_keys).each { |key| stop_subscription(key) }

        # Start new subscriptions
        new_entries = {}
        (new_keys - old_keys).each do |key|
          spec = new_by_key[key]
          new_entries[key] = start_subscription(spec)
        end

        # Keep existing (check max_rate changes)
        kept = {}
        (new_keys & old_keys).each do |key|
          kept[key] = @subscriptions[key]
          check_max_rate(key, new_by_key[key])
        end

        @subscriptions = kept.merge(new_entries)
        @subscription_keys = new_sorted_keys
      end

      # Start a new subscription (timer or renderer).
      def start_subscription(spec)
        if spec.type == :every
          start_timer_subscription(spec)
        else
          start_renderer_subscription(spec)
        end
      end

      # Stop a subscription by key.
      def stop_subscription(key)
        entry = @subscriptions.delete(key)
        return unless entry

        case entry[:sub_type]
        when :timer
          entry[:thread]&.kill
        when :renderer
          @bridge.send_encoded(
            Protocol::Encode.encode_unsubscribe(entry[:kind], @format)
          )
        end
      end

      # Start a timer subscription (runs locally, pushes to event queue).
      def start_timer_subscription(spec)
        queue = @event_queue
        tag = spec.tag
        interval = spec.interval

        thread = Thread.new do
          loop do
            sleep(interval / 1000.0)
            queue.push([:timer_tick, tag])
          end
        end
        thread.name = "plushie-timer-#{tag}"

        {sub_type: :timer, thread: thread, tag: tag, interval: interval}
      end

      # Start a renderer subscription (send subscribe message to bridge).
      def start_renderer_subscription(spec)
        @bridge.send_encoded(
          Protocol::Encode.encode_subscribe(spec.type, spec.tag, @format, max_rate: spec.max_rate)
        )

        {sub_type: :renderer, kind: spec.type, tag: spec.tag, max_rate: spec.max_rate}
      end

      # Update max_rate on existing renderer subscriptions if changed.
      def update_max_rates(new_by_key)
        new_by_key.each do |key, spec|
          check_max_rate(key, spec)
        end
      end

      # Check if a single subscription's max_rate needs updating.
      def check_max_rate(key, spec)
        entry = @subscriptions[key]
        return unless entry && entry[:sub_type] == :renderer && entry[:max_rate] != spec.max_rate

        # Re-send subscribe with new rate
        @bridge.send_encoded(
          Protocol::Encode.encode_subscribe(spec.type, spec.tag, @format, max_rate: spec.max_rate)
        )
        @subscriptions[key] = entry.merge(max_rate: spec.max_rate)
      end
    end
  end
end

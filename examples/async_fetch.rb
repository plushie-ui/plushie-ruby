# frozen_string_literal: true

require "plushie"

# Async command example -- a button that triggers background work.
#
# Demonstrates:
# - Command.async for off-thread work
# - Pattern matching on Event::Async for success/error
# - Loading state management
class AsyncFetch
  include Plushie::App

  Model = Plushie::Model.define(:status, :result, :error)

  def init(_opts)
    Model.new(status: :idle, result: nil, error: nil)
  end

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "fetch"]
      cmd = Command.async(
        -> {
          # Simulate a slow network call
          sleep(0.5)
          [:ok, "Fetched at #{Time.now.utc.strftime("%H:%M:%S")}"]
        },
        :fetch_result
      )
      [model.with(status: :loading, result: nil, error: nil), cmd]

    in Event::Async[tag: :fetch_result, result: [:ok, value]]
      model.with(status: :done, result: value)

    in Event::Async[tag: :fetch_result, result: [:error, reason]]
      model.with(status: :error, error: reason.to_s)

    else
      model
    end
  end

  def view(model)
    window("main", title: "Async Fetch") do
      column(padding: 24, spacing: 16, width: :fill) do
        text("header", "Async Command Demo", size: 20)
        button("fetch", "Fetch Data")
        status_message(model)
      end
    end
  end

  private

  def status_message(model)
    case model.status
    when :idle
      text("status", "Press the button to start", color: "#888888")
    when :loading
      text("status", "Loading...", color: "#cc8800")
    when :done
      column(spacing: 4) do
        text("label", "Result:", size: 14)
        text("result", model.result, color: "#22aa44")
      end
    when :error
      text("error", "Error: #{model.error}", color: "#cc2222")
    end
  end
end

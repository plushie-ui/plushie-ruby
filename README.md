# plushie

Build native desktop apps in Ruby. **Pre-1.0**

Plushie is a desktop GUI framework that allows you to write your entire
application in Ruby -- state, events, UI -- and get native windows
on Linux, macOS, and Windows. Rendering is powered by
[iced](https://github.com/iced-rs/iced), a cross-platform GUI library
for Rust, which plushie drives as a precompiled binary behind the scenes.

```ruby
class Counter
  include Plushie::App

  Model = Plushie::Model.define(:count)

  def init(_opts) = Model.new(count: 0)

  def update(model, event)
    case event
    in Event::Widget[type: :click, id: "inc"]
      model.with(count: model.count + 1)
    in Event::Widget[type: :click, id: "dec"]
      model.with(count: model.count - 1)
    else
      model
    end
  end

  def view(model)
    window("main", title: "Counter") do
      column(padding: 16, spacing: 8) do
        text("count", "Count: #{model.count}")
        row(spacing: 8) do
          button("inc", "+")
          button("dec", "-")
        end
      end
    end
  end
end

Plushie.run(Counter)
```

## Getting started

Add plushie to your Gemfile:

```ruby
gem "plushie", "== 0.1.0"
```

Then:

```bash
bundle install
# TODO: plushie download  -- download precompiled binary
```

Requires Ruby 3.2+. The precompiled binary requires no Rust toolchain.

## How it works

Your Ruby code sends widget trees to a renderer over stdin; the
renderer draws native windows and sends user events back over stdout.

You don't need Rust to use plushie. The renderer is a precompiled
binary, similar to how your app talks to a database without you
writing C.

## Development

```bash
bundle exec rake test      # run tests
bundle exec rake standard  # lint
bundle exec rake           # both
```

## License

MIT

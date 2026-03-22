# frozen_string_literal: true

# Load Plushie Rake tasks.
#
# Add to your Rakefile:
#   require "plushie/rake"
#
# Available tasks:
#   plushie:download  -- download precompiled renderer binary
#   plushie:run       -- run a Plushie app
#   plushie:inspect   -- print UI tree as JSON
#   plushie:preflight -- run all CI checks

require "rake"

namespace :plushie do
  desc "Download the precompiled plushie renderer binary"
  task :download do
    require "plushie"
    Plushie::Binary.download!
    puts "Downloaded plushie binary to #{Plushie::Binary.downloaded_path}"
  end

  desc "Run a Plushie app (e.g. rake plushie:run[Counter])"
  task :run, [:app_class] do |_t, args|
    unless args[:app_class]
      abort "Usage: rake plushie:run[AppClass]"
    end
    require "plushie"
    app_class = Object.const_get(args[:app_class])
    Plushie.run(app_class)
  end

  desc "Print the initial UI tree as JSON"
  task :inspect, [:app_class] do |_t, args|
    unless args[:app_class]
      abort "Usage: rake plushie:inspect[AppClass]"
    end
    require "plushie"
    require "json"
    app_class = Object.const_get(args[:app_class])
    app = app_class.new
    model = app.init({})
    model = model.is_a?(Array) ? model.first : model
    tree = Plushie::Tree.normalize(app.view(model))
    node = tree.is_a?(Array) ? tree.first : tree
    wire = Plushie::Tree.node_to_wire(node)
    puts JSON.pretty_generate(wire)
  end

  desc "Run all CI checks (standard + test)"
  task :preflight do
    sh "bundle exec rake standard"
    sh "bundle exec rake test"
    puts "\nAll checks passed."
  end
end

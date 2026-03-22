# frozen_string_literal: true

require_relative "lib/plushie/version"

Gem::Specification.new do |spec|
  spec.name = "plushie"
  spec.version = Plushie::VERSION
  spec.authors = ["Daniel Hedlund"]
  spec.email = ["daniel@digitree.org"]

  spec.summary = "Native desktop GUI framework for Ruby, powered by iced"
  spec.description = "Build native desktop apps in Ruby using the Elm architecture. " \
    "Rendering is handled by a precompiled binary built on iced."
  spec.homepage = "https://github.com/plushie-ui/plushie-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ .git .standard])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "msgpack", "~> 1.7"
  spec.add_dependency "logger"
end

# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

require "standard/rake"

desc "Run Steep type checker"
task :steep do
  unless system("bundle exec steep --version", out: File::NULL, err: File::NULL)
    abort "steep is not available (may not support this Ruby version)"
  end
  sh "bundle exec steep check"
end

desc "Generate YARD documentation"
task :yard do
  sh "bundle exec yard doc"
end

task default: %i[test standard steep]

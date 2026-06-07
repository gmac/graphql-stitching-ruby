# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t, args|
  puts args
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

namespace :benchmark do
  desc "Benchmark planner throughput"
  task :planner do
    ruby "benchmark/run.rb"
  end
end

desc "Run benchmarks"
task benchmark: "benchmark:planner"

task :default => :test

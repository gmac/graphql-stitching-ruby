# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t, args|
  puts args
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList['test/**/*_test.rb']
end

task :default => :test
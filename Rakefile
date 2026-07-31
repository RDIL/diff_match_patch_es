# frozen_string_literal: true

require 'minitest/test_task'

Minitest::TestTask.create

desc 'Run the static parity corpus through both implementations and compare'
task :parity do
  dir = File.expand_path('parity', __dir__)
  sh 'yarn install --immutable', chdir: dir
  sh 'node run_js.mjs', chdir: dir
  sh 'ruby run_ruby.rb', chdir: dir
  sh 'ruby compare.rb', chdir: dir
end

task default: :test

# frozen_string_literal: true

require "rutidy"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.example_status_persistence_file_path = ".rspec_status"
  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed
end

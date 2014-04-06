require 'coveralls'
require 'simplecov'
require 'timecop'
require 'tmpdir'
require 'vcr'
require 'webmock/rspec'

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter,
]
SimpleCov.start do
  add_filter Bundler.bundle_path.to_s
  add_filter File.dirname(__FILE__)

  # Kaede::Scheduler is tested in another process.
  add_filter 'lib/kaede/scheduler.rb'
end

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr'
  config.hook_into :webmock
end

RSpec.configure do |config|
  # config.profile_examples = 10

  config.order = :random
  Kernel.srand config.seed

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.syntax = :expect
    mocks.verify_partial_doubles = true
  end

  config.before :each do
    @topdir = Pathname.new(__FILE__).parent
  end

  config.around :each do |example|
    Dir.mktmpdir('kaede') do |dir|
      @tmpdir = Pathname.new(dir)
      example.run
    end
  end
end

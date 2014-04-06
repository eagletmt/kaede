# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'kaede/version'

Gem::Specification.new do |spec|
  spec.name          = "kaede"
  spec.version       = Kaede::VERSION
  spec.authors       = ["Kohei Suzuki"]
  spec.email         = ["eagletmt@gmail.com"]
  spec.summary       = %q{Scheduler for recpt1 recorder using Syoboi Calendar}
  spec.description   = %q{Scheduler for recpt1 recorder using Syoboi Calendar}
  spec.homepage      = "https://github.com/eagletmt/kaede"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.0.0.beta2"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "timecop"
  spec.add_development_dependency "vcr"
  spec.add_development_dependency "webmock"
  spec.add_dependency "nokogiri"
  spec.add_dependency "redis"
  spec.add_dependency "sleepy_penguin"
  spec.add_dependency "sqlite3"
  spec.add_dependency "thor"
  spec.add_dependency "twitter"
end

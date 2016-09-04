require "bundler/gem_tasks"

task :default => :spec

require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new(:spec)

desc 'Generate gRPC codes'
task :grpc do
  cd 'lib'
  sh 'protoc --ruby_out=. --go_out=plugins=grpc:../kaede-cli --plugin=protoc-gen-grpc=`which grpc_ruby_plugin` --grpc_out=. kaede/grpc/kaede.proto'
end

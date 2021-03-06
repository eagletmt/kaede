require 'pathname'
require 'redis'

module Kaede
  class Config
    attr_accessor :database_url, :redis, :redis_queue, :fluent_tag_prefix, :fluent_host, :fluent_port, :grpc_port

    path_attrs = [:b25, :recpt1, :assdumper, :clean_ts, :statvfs, :record_dir, :cache_dir, :cabinet_dir]
    attr_reader *path_attrs
    path_attrs.each do |attr|
      define_method("#{attr}=") do |arg|
        instance_variable_set("@#{attr}", Pathname.new(arg))
      end
    end

    def initialize
      self.b25 = '/usr/bin/b25'
      self.recpt1 = '/usr/bin/recpt1'
      self.assdumper = '/usr/bin/assdumper'
      self.clean_ts = '/usr/bin/clean-ts'
      self.statvfs = '/usr/bin/statvfs'
      basedir = Pathname.new(ENV['HOME']).join('kaede')
      self.database_url = "sqlite://#{basedir.join('kaede.db')}"
      self.record_dir = basedir.join('records')
      self.cache_dir = basedir.join('cache')
      self.cabinet_dir = basedir.join('cabinet')
      self.redis = Redis.new
      self.redis_queue = 'jobs'
      self.grpc_port = 'localhost:4195'
    end
  end
end

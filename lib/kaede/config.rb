require 'pathname'
require 'redis'

module Kaede
  class Config
    attr_accessor :redis, :redis_queue, :twitter, :twitter_target

    path_attrs = [:b25, :recpt1, :assdumper, :clean_ts, :statvfs, :database_path, :record_dir, :cache_dir, :cabinet_dir]
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
      self.database_path = basedir.join('kaede.db')
      self.record_dir = basedir.join('records')
      self.cache_dir = basedir.join('cache')
      self.cabinet_dir = basedir.join('cabinet')
      self.twitter = nil
      self.twitter_target = nil
      self.redis = Redis.new
      self.redis_queue = 'jobs'
    end
  end
end

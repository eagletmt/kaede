require 'thor'

module Kaede
  class CLI < Thor
    package_name 'kaede'

    class_option :config,
      desc: 'Path to config file',
      banner: 'PATH',
      type: :string,
      aliases: :c

    desc 'scheduler', 'Start scheduler'
    def scheduler
      require 'kaede/database'
      require 'kaede/scheduler'
      load_config

      db = Kaede::Database.new(Kaede.config.database_url)
      Kaede::Scheduler.setup(db)
      Kaede::Scheduler.start
    end

    desc 'db-prepare', 'Create tables'
    def db_prepare
      require 'kaede/database'
      load_config

      db = Kaede::Database.new(Kaede.config.database_url)
      db.prepare_tables
    end

    private

    def load_config
      require 'kaede'
      require 'kaede/grpc/kaede_services_pb'
      if path = options[:config]
        load File.realpath(path)
      end
    end
  end
end

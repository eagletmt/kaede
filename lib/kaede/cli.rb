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

      db = Kaede::Database.new(Kaede.config.database_path)
      Kaede::Scheduler.setup(db)
      Kaede::Scheduler.start
    end

    desc 'add-channel NAME', 'Add available channel'
    option :recorder,
      desc: 'Channel number for the recorder',
      banner: 'CH',
      type: :numeric,
      required: true
    option :syoboi,
      desc: 'Channel number for Syoboi Calendar',
      banner: 'CH',
      type: :numeric,
      required: true
    def add_channel(name)
      require 'kaede/database'
      require 'kaede/channel'
      load_config

      db = Kaede::Database.new(Kaede.config.database_path)
      db.add_channel(Channel.new(nil, name, options[:recorder], options[:syoboi]))
    end

    desc 'add-tid TID', 'Add tracking title'
    def add_tid(tid)
      require 'kaede/database'
      load_config

      db = Kaede::Database.new(Kaede.config.database_path)
      db.add_tracking_title(tid.to_i)
    end

    desc 'update', 'Update jobs and programs by Syoboi Calendar'
    def update
      require 'kaede/database'
      require 'kaede/syoboi_calendar'
      require 'kaede/updater'
      load_config

      db = Kaede::Database.new(Kaede.config.database_path)
      syobocal = Kaede::SyoboiCalendar.new
      Kaede::Updater.new(db, syobocal).update
    end

    private

    def load_config
      require 'kaede'
      if path = options[:config]
        load path
      end
    end
  end
end

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

      db = Kaede::Database.new(Kaede.config.database_url)
      db.add_channel(Channel.new(nil, name, options[:recorder], options[:syoboi]))
    end

    desc 'add-tid TID', 'Add tracking title'
    def add_tid(tid)
      load_config
      p stub.add_tid(Kaede::Grpc::AddTidInput.new(tid: tid.to_i)).to_h
    end

    desc 'reload-scheduler', 'Reload scheduler'
    def reload_scheduler
      load_config

      stub.reload(Kaede::Grpc::SchedulerReloadInput.new)
    end

    desc 'stop-scheduler', 'Stop scheduler'
    def stop_scheduler
      load_config

      stub.stop(Kaede::Grpc::SchedulerStopInput.new)
    end

    desc 'list-programs', 'List programs'
    def list_programs
      require 'json'
      load_config

      stub.get_programs(Kaede::Grpc::GetProgramsInput.new).programs.each do |program|
        show_program(program)
      end
    end

    desc 'update', 'Update jobs and programs by Syoboi Calendar'
    def update
      require 'kaede/database'
      require 'kaede/syoboi_calendar'
      require 'kaede/updater'
      load_config

      db = Kaede::Database.new(Kaede.config.database_url)
      syobocal = Kaede::SyoboiCalendar.new
      Kaede::Updater.new(db, syobocal).update
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

    def stub
      @stub ||= Kaede::Grpc::Scheduler::Stub.new(Kaede.config.grpc_port, :this_channel_is_insecure)
    end

    def show_program(program)
      h = program.to_h
      decode_time(h, :start_time)
      decode_time(h, :end_time)
      decode_time(h, :enqueued_at)
      puts JSON.dump(h)
    end

    def decode_time(h, key)
      t = h[key]
      h[key] = Time.at(t.seconds, t.nanos / 1000)
    end
  end
end

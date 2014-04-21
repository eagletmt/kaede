require 'dbus'
require 'set'
require 'kaede/dbus'
require 'kaede/dbus/scheduler'

module Kaede
  class Updater
    def initialize(db, syobocal)
      @db = db
      @syobocal = syobocal
    end

    def update
      channels = {}
      @db.get_channels.each do |ch|
        channels[ch.for_syoboi] = ch
      end
      tracking_titles = Set.new(@db.get_tracking_titles)
      jobs = {}
      @db.get_jobs.each do |job|
        jobs[job[:pid]] = job
      end

      programs = @syobocal.cal_chk(days: 7)
      @db.transaction do
        programs.each do |program|
          if channels.has_key?(program.channel_for_syoboi)
            update_program(program, channels[program.channel_for_syoboi], tracking_titles)
          end
          jobs.delete(program.pid)
        end
      end

      jobs.each_value do |job|
        puts "Program #{job[:pid]} has gone away. Delete its job #{job[:id]}"
        @db.delete_job(job[:id])
      end

      reload_scheduler
    end

    def update_program(program, channel, tracking_titles)
      @db.update_program(program, channel)
      if tracking_titles.include?(program.tid)
        add_job_for(program)
      end
    end

    JOB_TIME_GAP = 15 # seconds
    def add_job_for(program)
      @db.add_job(program.pid, program.start_time + program.start_offset - JOB_TIME_GAP)
      puts "Insert job for #{program.pid}"
    rescue SQLite3::ConstraintException => e
      if e.message != 'UNIQUE constraint failed: jobs.pid'
        raise e
      end
    end

    def reload_scheduler
      service = ::DBus.session_bus.service(DBus::DESTINATION)
      scheduler = service.object(DBus::Scheduler::PATH)
      scheduler.introspect
      scheduler.Reload
    end
  end
end

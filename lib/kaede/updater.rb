require 'set'
require 'kaede/grpc/kaede_services_pb'

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
        puts "Program #{job[:pid]} has gone away. Delete its job"
        @db.delete_job(job[:pid])
      end
    end

    def update_program(program, channel, tracking_titles)
      @db.update_program(program, channel)
      if tracking_titles.include?(program.tid)
        update_job_for(program)
      end
    end

    JOB_TIME_GAP = 15 # seconds
    def update_job_for(program)
      @db.update_job(program.pid, program.start_time + program.start_offset - JOB_TIME_GAP)
    end
  end
end

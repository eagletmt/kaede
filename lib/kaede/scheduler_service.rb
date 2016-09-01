require 'kaede/channel'
require 'kaede/grpc/kaede_services_pb'
require 'kaede/syoboi_calendar'
require 'kaede/updater'

module Kaede
  class SchedulerService < Grpc::Scheduler::Service
    def initialize(reload_event, stop_event, db)
      super()
      @reload_event = reload_event
      @stop_event = stop_event
      @db = db
      @programs = []
    end

    # RPC methods

    def reload(_input, _call)
      @reload_event.incr(1)
      Grpc::SchedulerReloadOutput.new
    end

    def stop(_input, _call)
      @stop_event.incr(1)
      Grpc::SchedulerStopOutput.new
    end

    def get_programs(_input, _call)
      Grpc::GetProgramsOutput.new(
        programs: @programs,
      )
    end

    def add_tid(input, _call)
      syobocal = Kaede::SyoboiCalendar.new
      titles = syobocal.title_medium(input.tid)
      if titles
        title = titles.fetch(input.tid.to_s).fetch('Title')
        @db.add_tracking_title(input.tid)
        Grpc::AddTidOutput.new(
          tid: input.tid,
          title: title,
        )
      else
        raise GRPC::BadStatus.new(GRPC::Core::StatusCodes::INVALID_ARGUMENT, 'No such TID')
      end
    rescue Sequel::UniqueConstraintViolation => e
      raise GRPC::BadStatus.new(GRPC::Core::StatusCodes::INVALID_ARGUMENT, e.message)
    end

    def add_channel(input, _call)
      @db.add_channel(Channel.new(nil, input.name, input.recorder, input.syoboi))
      Grpc::AddChannelOutput.new
    rescue Sequel::UniqueConstraintViolation => e
      raise GRPC::BadStatus.new(GRPC::Core::StatusCodes::INVALID_ARGUMENT, e.message)
    end

    def update(_input, _call)
      syobocal = Kaede::SyoboiCalendar.new
      Kaede::Updater.new(@db, syobocal).update
      @reload_event.incr(1)
      Grpc::UpdateOutput.new
    end

    # Public methods

    def add_program(program, enqueued_at)
      @programs.push(
        Grpc::Program.new(
          pid: program.pid,
          tid: program.tid,
          start_time: encode_timestamp(program.start_time),
          end_time: encode_timestamp(program.end_time),
          channel_name: program.channel_name,
          channel_for_syoboi: program.channel_for_syoboi,
          channel_for_recorder: program.channel_for_recorder,
          count: program.count,
          start_offset: program.start_offset,
          subtitle: program.subtitle,
          title: program.title,
          comment: program.comment,
          enqueued_at: encode_timestamp(enqueued_at),
        )
      )
    end

    private

    def encode_timestamp(time)
      Google::Protobuf::Timestamp.new(seconds: time.to_i, nanos: time.nsec)
    end
  end
end

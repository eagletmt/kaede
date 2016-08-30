require 'kaede/grpc/kaede_services_pb'

module Kaede
  class SchedulerService < Grpc::Scheduler::Service
    def initialize(reload_event, stop_event)
      super()
      @reload_event = reload_event
      @stop_event = stop_event
      @programs = []
    end

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

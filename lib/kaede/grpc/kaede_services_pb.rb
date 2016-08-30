# Generated by the protocol buffer compiler.  DO NOT EDIT!
# Source: kaede/grpc/kaede.proto for package 'kaede.grpc'

require 'grpc'
require 'kaede/grpc/kaede_pb'

module Kaede
  module Grpc
    module Scheduler
      class Service

        include GRPC::GenericService

        self.marshal_class_method = :encode
        self.unmarshal_class_method = :decode
        self.service_name = 'kaede.grpc.Scheduler'

        rpc :Reload, SchedulerReloadInput, SchedulerReloadOutput
        rpc :Stop, SchedulerStopInput, SchedulerStopOutput
        rpc :GetPrograms, GetProgramsInput, GetProgramsOutput
        rpc :AddTid, AddTidInput, AddTidOutput
        rpc :Update, UpdateInput, UpdateOutput
      end

      Stub = Service.rpc_stub_class
    end
  end
end

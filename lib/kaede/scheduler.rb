require 'thread'
require 'sleepy_penguin'
require 'kaede/notifier'
require 'kaede/scheduler_service'

module Kaede
  module Scheduler
    extend self

    def setup(db)
      @db = db
      prepare_events
      $stdout.sync = true
      $stderr.sync = true
      @recorder_queue = Queue.new
      @recorder_waiter = start_recorder_waiter
      $0 = 'kaede-scheduler'
      puts "Start #{Process.pid}"
    end

    POISON = Object.new

    def prepare_events
      @reload_event = SleepyPenguin::EventFD.new(0, :SEMAPHORE)
      @stop_event = SleepyPenguin::EventFD.new(0, :SEMAPHORE)
    end

    def fire_stop
      @stop_event.incr(1)
    end

    def start_recorder_waiter
      Thread.start do
        loop do
          recorder_thread = @recorder_queue.deq
          break if recorder_thread.equal?(POISON)
          recorder_thread.join
        end
      end
    end

    def start
      catch(:stop) do
        loop do
          start_epoll
        end
      end
      @recorder_queue.enq(POISON)
      @recorder_waiter.join
    end

    def prepare_timerfds
      @timerfds = {}
      @db.get_jobs.each do |job|
        tfd = SleepyPenguin::TimerFD.new(:REALTIME)
        tfd.settime(:ABSTIME, 0, job[:enqueued_at].to_i)
        @timerfds[tfd.fileno] = [tfd, job[:pid]]
      end
      @timerfds
    end

    def prepare_epoll
      prepare_timerfds
      SleepyPenguin::Epoll.new.tap do |epoll|
        epoll.add(@reload_event, [:IN])
        epoll.add(@stop_event, [:IN])
        @timerfds.each_value do |tfd, _|
          epoll.add(tfd, [:IN])
        end
      end
    end

    def start_epoll
      epoll = prepare_epoll
      puts "Loaded #{@timerfds.size} schedules"
      start_grpc

      catch(:reload) do
        epoll_loop(epoll)
      end
    ensure
      epoll.close
      stop_grpc
    end

    def epoll_loop(epoll)
      loop do
        epoll.wait do |events, io|
          case io
          when SleepyPenguin::TimerFD
            io.expirations
            _, pid = @timerfds.delete(io.fileno)
            thread = spawn_recorder(pid)
            @recorder_queue.enq(thread)
          when @reload_event
            io.value
            throw :reload
          when @stop_event
            io.value
            $0 = "kaede-scheduler (old #{Time.now.strftime('%F %X')})"
            throw :stop
          else
            abort "Unknown IO: #{io.inspect}"
          end
        end
      end
    end

    def start_grpc
      service = SchedulerService.new(@reload_event, @stop_event)
      load_grpc_programs(service)
      @grpc_thread = start_grpc_loop(service)
    end

    def load_grpc_programs(service)
      programs = @db.get_programs(@timerfds.values.map { |_, pid| pid })
      now = Time.now
      @timerfds.each_value do |tfd, pid|
        _, value = tfd.gettime
        program = programs[pid]
        service.add_program(programs[pid], now + value)
      end
    end

    def start_grpc_loop(service)
      @rpc_server = GRPC::RpcServer.new
      @rpc_server.add_http2_port(Kaede.config.grpc_port, :this_port_is_insecure)
      @rpc_server.handle(service)
      Thread.start { @rpc_server.run }
    end

    def stop_grpc
      @rpc_server.stop
      @grpc_thread.join
    end

    def spawn_recorder(pid)
      Thread.start do
        begin
          require 'kaede/recorder'
          Recorder.new(Notifier.new).record(@db, pid)
          @db.mark_finished(pid)
        rescue Exception => e
          $stderr.puts "Failed job for #{pid}: #{e.class}: #{e.message}"
          e.backtrace.each do |bt|
            $stderr.puts "  #{bt}"
          end
        end
      end
    end
  end
end

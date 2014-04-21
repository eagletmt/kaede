require 'dbus'
require 'thread'
require 'sleepy_penguin'
require 'kaede/dbus/program'

module Kaede
  module Scheduler
    extend self

    def setup(db)
      @db = db
      setup_signals
      $stdout.sync = true
      $stderr.sync = true
      puts "Start #{Process.pid}"
    end

    def setup_signals
      @reload_event = SleepyPenguin::EventFD.new(0, :SEMAPHORE)
      trap(:HUP) { @reload_event.incr(1) }

      @stop_event = SleepyPenguin::EventFD.new(0, :SEMAPHORE)
      trap(:INT) { @stop_event.incr(1) }
    end

    def start
      catch(:stop) do
        loop do
          start_epoll
        end
      end
    end

    def start_epoll
      epoll = SleepyPenguin::Epoll.new
      epoll.add(@reload_event, [:IN])
      epoll.add(@stop_event, [:IN])

      @timerfds = {}
      @db.get_jobs.each do |job|
        tfd = SleepyPenguin::TimerFD.new(:REALTIME)
        tfd.settime(:ABSTIME, 0, job[:enqueued_at].to_i)
        epoll.add(tfd, [:IN])
        @timerfds[tfd.fileno] = [tfd, job[:id]]
      end
      puts "Loaded #{@timerfds.size} schedules"
      start_dbus

      catch(:reload) do
        epoll_loop(epoll)
      end
    ensure
      epoll.close
      stop_dbus
    end

    def epoll_loop(epoll)
      loop do
        epoll.wait do |events, io|
          case io
          when SleepyPenguin::TimerFD
            io.expirations
            _, id = @timerfds.delete(io.fileno)
            spawn_recorder(id)
          when @reload_event
            io.value
            throw :reload
          when @stop_event
            io.value
            throw :stop
          else
            abort "Unknown IO: #{io.inspect}"
          end
        end
      end
    end

    DBUS_DESTINATION = 'cc.wanko.kaede1'
    def start_dbus
      bus = ::DBus.session_bus
      service = bus.request_service(DBUS_DESTINATION)
      programs = @db.get_programs_from_job_ids(@timerfds.values.map { |_, id| id })
      @timerfds.each_value do |tfd, id|
        _, value = tfd.gettime
        program = programs[id]
        service.export(DBus::Program.new(program))
      end
      @dbus_main = ::DBus::Main.new
      @dbus_main << bus
      @dbus_thread = Thread.start do
        @dbus_main.run
      end
    end

    DBUS_STOP_TIMEOUT = 5
    def stop_dbus
      return unless @dbus_main
      @dbus_main.quit
      begin
        unless @dbus_thread.join(DBUS_STOP_TIMEOUT)
          @dbus_thread.kill
        end
      rescue Exception => e
        $stderr.puts "Exception on DBus thread: #{e.class}: #{e.message}"
        e.backtrace.each do |bt|
          $stderr.puts "  #{bt}"
        end
      end
      @dbus_main = nil
      @dbus_thread = nil
      ::DBus.session_bus.proxy.ReleaseName(DBUS_DESTINATION)
    end

    def spawn_recorder(job_id)
      Thread.start do
        begin
          require 'kaede/recorder'
          Recorder.new.record(@db, job_id)
          @db.mark_finished(job_id)
        rescue Exception => e
          $stderr.puts "Failed job #{job_id}: #{e.class}: #{e.message}"
          e.backtrace.each do |bt|
            $stderr.puts "  #{bt}"
          end
        end
      end
    end
  end
end

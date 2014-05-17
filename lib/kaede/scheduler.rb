require 'dbus'
require 'thread'
require 'sleepy_penguin'
require 'kaede/dbus'
require 'kaede/dbus/main'
require 'kaede/dbus/program'
require 'kaede/dbus/scheduler'
require 'kaede/notifier'

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

    def start_dbus
      bus = ::DBus.system_bus
      service = bus.request_service(DBus::DESTINATION)
      dbus_export_programs(service)
      service.export(DBus::Scheduler.new(@reload_event, @stop_event))

      @dbus_thread = start_dbus_loop(bus)
    end

    def dbus_export_programs(service)
      programs = @db.get_programs(@timerfds.values.map { |_, pid| pid })
      @timerfds.each_value do |tfd, pid|
        _, value = tfd.gettime
        program = programs[pid]
        obj = DBus::Program.new(program, Time.now + value)
        service.export(obj)

        # ruby-dbus doesn't emit properties when Introspect is requested.
        # Kaede manually creates Introspect XML so that `gdbus introspect` outputs properties.
        node = service.get_node(obj.path)
        node.singleton_class.class_eval do
          define_method :to_xml do
            obj.to_xml
          end
        end
      end
    end

    def start_dbus_loop(bus)
      @dbus_main = DBus::Main.new
      @dbus_main << bus
      Thread.start do
        max_retries = 10
        retries = 0
        begin
          @dbus_main.loop
        rescue ::DBus::Connection::NameRequestError => e
          puts "#{e.class}: #{e.message}"
          if retries < max_retries
            retries += 1
            sleep 1
            retry
          end
        end
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
      ::DBus.system_bus.proxy.ReleaseName(DBus::DESTINATION)
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

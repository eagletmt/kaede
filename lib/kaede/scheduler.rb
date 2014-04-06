require 'thread'
require 'sleepy_penguin'

module Kaede
  module Scheduler
    extend self

    def setup(db)
      @db = db
      setup_signals
      puts "Start #{Process.pid}"
    end

    def setup_signals
      @reload_event = SleepyPenguin::EventFD.new(0, :SEMAPHORE)
      trap(:HUP) { @reload_event.incr(1) }

      @stop_event = SleepyPenguin::EventFD.new(0, :SEMAPHORE)
      trap(:INT) { @stop_event.incr(1) }

      @list_event = SleepyPenguin::EventFD.new(0, :SEMAPHORE)
      trap(:USR1) { @list_event.incr(1) }
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
      epoll.add(@list_event, [:IN])

      timerfds = {}
      @db.get_jobs.each do |job|
        tfd = SleepyPenguin::TimerFD.new(:REALTIME)
        tfd.settime(:ABSTIME, 0, job[:enqueued_at].to_i)
        epoll.add(tfd, [:IN])
        timerfds[tfd.fileno] = [tfd, job[:id]]
      end
      puts "Loaded #{timerfds.size} schedules"

      catch(:reload) do
        epoll_loop(epoll, timerfds)
      end
    ensure
      epoll.close
    end

    def epoll_loop(epoll, timerfds)
      loop do
        epoll.wait do |events, io|
          case io
          when SleepyPenguin::TimerFD
            io.expirations
            _, id = timerfds.delete(io.fileno)
            spawn_recorder(id)
          when @reload_event
            io.value
            throw :reload
          when @stop_event
            io.value
            throw :stop
          when @list_event
            io.value
            if timerfds.empty?
              puts "No schedules"
            else
              programs = @db.get_programs_from_job_ids(timerfds.values.map { |_, id| id })
              timerfds.each_value do |tfd, id|
                _, value = tfd.gettime
                program = programs[id]
                puts "Invoke #{id} at #{Time.now + value}: #{program.syoboi_url}"
                puts "    #{program.formatted_fname}"
              end
            end
          else
            abort "Unknown IO: #{io.inspect}"
          end
        end
      end
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

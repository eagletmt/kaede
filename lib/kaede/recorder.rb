require 'date'
require 'fileutils'
require 'json'
require 'open3'

module Kaede
  class Recorder
    def initialize(notifier)
      @notifier = notifier
    end

    def record(db, pid)
      program = db.get_program(pid)
      before_record(program)

      puts "Start #{pid} #{program.syoboi_url}"
      do_record(program)

      program = db.get_program(pid)
      puts "Done #{pid} #{program.syoboi_url}"
      after_record(program)
    rescue Exception => e
      @notifier.notify_exception(e, program)
      raise e
    end

    def record_path(program)
      Kaede.config.record_dir.join("#{program.tid}_#{program.pid}.ts")
    end

    def cache_path(program)
      Kaede.config.cache_dir.join("#{program.tid}_#{program.pid}.cache.ts")
    end

    def cache_ass_path(program)
      Kaede.config.cache_dir.join("#{program.tid}_#{program.pid}.raw.ass")
    end

    def cabinet_path(program)
      Kaede.config.cabinet_dir.join("#{program.formatted_fname}.ts")
    end

    def cabinet_ass_path(program)
      Kaede.config.cabinet_dir.join("#{program.formatted_fname}.raw.ass")
    end

    def do_record(program)
      spawn_recpt1(program)
      spawn_tail(program)
      spawn_b25(program)
      spawn_ass(program)
      spawn_repeater
      wait_recpt1
      finalize
    end

    def spawn_recpt1(program)
      path = record_path(program)
      path.open('w') {}
      @recpt1_pid = spawn(Kaede.config.recpt1.to_s, program.channel_for_recorder.to_s, calculate_duration(program).to_s, path.to_s)
    end

    def calculate_duration(program)
      duration = (program.end_time - program.start_time).to_i - 10
      end_datetime = program.end_time.to_datetime
      if end_datetime.sunday? && end_datetime.hour == 22 && end_datetime.min == 27
        # For MX
        duration += 3 * 60
      elsif program.channel_name =~ /NHK/
        # For NHK
        duration += 25
      end
      duration
    end

    def spawn_tail(program)
      @tail_pipe_r, @tail_pipe_w = IO.pipe
      @tail_pid = spawn('tail', '-f', record_path(program).to_s, out: @tail_pipe_w)
      @tail_pipe_w.close
    end

    def spawn_b25(program)
      @b25_pipe_r, @b25_pipe_w = IO.pipe
      @b25_pid = spawn(Kaede.config.b25.to_s, '-v0', '-s1', '-m1', '/dev/stdin', cache_path(program).to_s, in: @b25_pipe_r)
      @b25_pipe_r.close
    end

    def spawn_ass(program)
      @ass_pipe_r, @ass_pipe_w = IO.pipe
      @ass_pid = spawn(Kaede.config.assdumper.to_s, '/dev/stdin', in: @ass_pipe_r, out: cache_ass_path(program).to_s)
      @ass_pipe_r.close
    end

    BUFSIZ = 188 * 1024

    def spawn_repeater
      @repeater_thread = Thread.start do
        while buf = @tail_pipe_r.read(BUFSIZ)
          @b25_pipe_w.write(buf)
          @ass_pipe_w.write(buf)
        end
        @tail_pipe_r.close
        @b25_pipe_w.close
        @ass_pipe_w.close
      end
    end

    def wait_recpt1
      Process.waitpid(@recpt1_pid)
    end

    def finalize
      Process.kill(:INT, @tail_pid)
      Process.waitpid(@tail_pid)
      @repeater_thread.join
      Process.waitpid(@b25_pid)
      Process.waitpid(@ass_pid)
    end

    def before_record(program)
      @notifier.notify_before_record(program)
    end

    def after_record(program)
      @notifier.notify_after_record(program)
      move_ass_to_cabinet(program)
      clean_ts(program)
      verify_duration(program, cache_path(program)) && verify_duration(program, cabinet_path(program))
      enqueue_to_redis(program)
      FileUtils.rm(cache_path(program).to_s)
    end

    def move_ass_to_cabinet(program)
      ass_path = cache_ass_path(program)
      if ass_path.size == 0
        ass_path.unlink
      else
        FileUtils.mv(ass_path.to_s, cabinet_ass_path(program).to_s)
      end
    end

    def clean_ts(program)
      unless system(Kaede.config.clean_ts.to_s, cache_path(program).to_s, cabinet_path(program).to_s)
        raise "clean-ts failure: #{program.formatted_fname}"
      end
    end

    def enqueue_to_redis(program)
      Kaede.config.redis.rpush(Kaede.config.redis_queue, program.formatted_fname)
    end

    ALLOWED_DURATION_ERROR = 20

    def verify_duration(program, path)
      expected_duration = calculate_duration(program)
      json = ffprobe(path)
      got_duration = json['duration'].to_f
      if (got_duration - expected_duration).abs < ALLOWED_DURATION_ERROR
        true
      else
        @notifier.notify_duration_error(program, got_duration)
        false
      end
    end

    class FFprobeError < StandardError
    end

    def ffprobe(path)
      outbuf, errbuf, status = Open3.capture3('ffprobe', '-show_format', '-print_format', 'json', path.to_s)
      if status.success?
        JSON.parse(outbuf)['format']
      else
        raise FFprobeError.new("ffprobe exited with #{status.exitstatus}: #{errbuf}")
      end
    end
  end
end

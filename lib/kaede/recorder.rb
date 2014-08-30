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

    class TailF
      def initialize(path, cmd, options = {})
        @path = path
        @cmd = cmd
        @options = options
      end

      def spawn
        @pipe_r, @pipe_w = IO.pipe
        @tail_pid = Kernel.spawn('tail', '-f', @path.to_s, out: @pipe_w)
        @pid = Kernel.spawn(*@cmd, @options.merge(in: @pipe_r))
        @pipe_r.close
        @pipe_w.close
        self
      end

      def kill
        Process.kill(:INT, @tail_pid)
        Process.waitpid(@tail_pid)
        Process.waitpid(@pid)
      end
    end

    def do_record(program)
      recpt1_pid = spawn_recpt1(program)
      b25_tailf = spawn_b25(program)
      ass_tailf = spawn_ass(program)
      Process.waitpid(recpt1_pid)
      [b25_tailf, ass_tailf].each do |tailf|
        tailf.kill
      end
    end

    def spawn_recpt1(program)
      path = record_path(program)
      path.open('w') {}
      spawn(Kaede.config.recpt1.to_s, program.channel_for_recorder.to_s, calculate_duration(program).to_s, path.to_s)
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

    def spawn_b25(program)
      TailF.new(record_path(program), [
        Kaede.config.b25.to_s,
        '-v0',
        '-s1',
        '-m1',
        '/dev/stdin',
        cache_path(program).to_s,
      ], {}).spawn
    end

    def spawn_ass(program)
      TailF.new(record_path(program), [
        Kaede.config.assdumper.to_s,
        '/dev/stdin',
      ], out: cache_ass_path(program).to_s).spawn
    end

    def before_record(program)
      @notifier.notify_before_record(program)
    end

    def after_record(program)
      @notifier.notify_after_record(program)
      unless verify_duration(program, cache_path(program))
        redo_ts_process(program)
      end
      move_ass_to_cabinet(program)
      clean_ts(program)
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

    def redo_ts_process(program)
      unless system(Kaede.config.b25.to_s, '-v0', '-s1', '-m1', record_path(program).to_s, cache_path(program).to_s)
        @notifier.notify_redo_error(program)
        return false
      end
      unless system(Kaede.config.assdumper.to_s, record_path(program).to_s, out: cache_ass_path(program).to_s)
        @notifier.notify_redo_error(program)
        return false
      end
      unless verify_duration(program, cache_path(program))
        @notifier.notify_redo_error(program)
        return false
      end
      true
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

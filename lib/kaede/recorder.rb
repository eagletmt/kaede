# coding: utf-8

require 'date'
require 'open3'
require 'fileutils'

module Kaede
  class Recorder
    def initialize
      @twitter = Kaede.config.twitter
    end

    def record(db, pid)
      program = db.get_program(pid)
      before_record(program)

      puts "Start #{pid} #{program.syoboi_url}"
      duration = calculate_duration(program)
      do_record(program, duration)

      program = db.get_program(pid)
      puts "Done #{pid} #{program.syoboi_url}"
      after_record(program)
    end

    def record_path(program)
      Kaede.config.record_dir.join("#{program.tid}_#{program.pid}.ts")
    end

    BUFSIZ = 188 * 16

    def do_record(program, duration)
      path = record_path(program)
      path.open('w') {}
      recpt1_pid = spawn(Kaede.config.recpt1.to_s, program.channel_for_recorder.to_s, duration.to_s, path.to_s)

      IO.pipe(binmode: true) do |r0, w0|
        tail_pid = spawn('tail', '-f', path.to_s, out: w0)
        w0.close

        IO.pipe do |r1, w1|
          b25_pid = spawn(Kaede.config.b25.to_s, '-v0', '-s1', '-m1', '/dev/stdin', Kaede.config.cache_dir.join("#{program.tid}_#{program.pid}.cache.ts").to_s, in: r1)
          r1.close

          IO.pipe do |r2, w2|
            ass_pid = spawn(Kaede.config.assdumper.to_s, '/dev/stdin', in: r2, out: Kaede.config.cache_dir.join("#{program.tid}_#{program.pid}.raw.ass").to_s)
            r2.close

            multi = Thread.start do
              while buf = r0.read(BUFSIZ)
                w1.write(buf)
                w2.write(buf)
              end
              w1.close
              w2.close
              Process.waitpid(b25_pid)
              Process.waitpid(ass_pid)
            end

            Process.waitpid(recpt1_pid)
            Process.kill(:INT, tail_pid)
            Process.waitpid(tail_pid)
            multi.join
          end
        end
      end
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

    def tweet(text)
      return unless @twitter
      Thread.start do
        begin
          @twitter.update(text)
        rescue Exception => e
          $stderr.puts "Failed to tweet: #{text}: #{e.class}: #{e.message}"
        end
      end
    end

    def before_record(program)
      tweet("#{format_title(program)}を録画する")
    end

    def after_record(program)
      tweet_after_record(program)

      fname = program.formatted_fname
      FileUtils.mv(Kaede.config.cache_dir.join("#{program.tid}_#{program.pid}.cache.ts").to_s, Kaede.config.cache_dir.join("#{fname}.cache.ts").to_s)
      ass_path = Kaede.config.cache_dir.join("#{program.tid}_#{program.pid}.raw.ass")
      if ass_path.size == 0
        ass_path.unlink
      else
        FileUtils.mv(ass_path.to_s, Kaede.config.cabinet_dir.join("#{fname}.raw.ass").to_s)
      end

      puts "clean-ts #{fname}.ts"
      unless system(Kaede.config.clean_ts.to_s, Kaede.config.cache_dir.join("#{fname}.cache.ts").to_s, Kaede.config.cabinet_dir.join("#{fname}.ts").to_s)
        raise "clean-ts failure: #{fname}"
      end

      puts "redis #{fname}.ts"
      Kaede.config.redis.rpush(Kaede.config.redis_queue, fname)

      FileUtils.rm(Kaede.config.cache_dir.join("#{fname}.cache.ts").to_s)
    end

    def tweet_after_record(program)
      path = record_path(program)
      total, avail = `#{Kaede.config.statvfs} #{Kaede.config.record_dir}`.chomp.split(/\s/, 2).map(&:to_i)
      avail /= 1024 * 1024 * 1024
      fsize = path.size.to_f
      fsize /= 1024 * 1024 * 1024
      msg = sprintf("%sを録画した。ファイルサイズ約%.2fGB。残り約%dGB\n", format_title(program), fsize, avail)
      tweet(msg)
    end

    def format_title(program)
      buf = "#{program.channel_name}で「#{program.title}"
      if program.count
        buf += " ##{program.count}"
      end
      buf += " #{program.subtitle}」"
      buf
    end
  end
end

# coding: utf-8
require 'kaede'

module Kaede
  class Notifier
    def initialize
      @twitter = Kaede.config.twitter
      @twitter_target = Kaede.config.twitter_target
    end

    def notify_before_record(program)
      tweet("#{format_title(program)}を録画する")
    end

    def notify_after_record(program)
      tweet(
        sprintf(
          "%sを録画した。ファイルサイズ約%.2fGB。残り約%dGB\n",
          format_title(program),
          ts_filesize(program),
          available_disk,
        )
      )
    end

    def notify_exception(exception, program)
      msg = "#{program.title}(PID #{program.pid}) の録画中に #{exception.class} で失敗した……"
      if @twitter_target
        msg = "@#{@twitter_target} #{msg}"
      end
      tweet(msg)
    end

    def notify_duration_error(program, got_duration)
      msg = sprintf('%sの長さが%g秒しか無いようだが……', format_title(program), got_duration)
      if @twitter_target
        msg = "@#{@twitter_target} #{msg}"
      end
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

    def ts_filesize(program)
      in_gigabyte(record_path(program).size.to_f)
    end

    # FIXME: duplicate
    def record_path(program)
      Kaede.config.record_dir.join("#{program.tid}_#{program.pid}.ts")
    end

    def available_disk
      _, avail = `#{Kaede.config.statvfs} #{Kaede.config.record_dir}`.chomp.split(/\s/, 2).map(&:to_i)
      in_gigabyte(avail)
    end

    def in_gigabyte(size)
      size / (1024 * 1024 * 1024)
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
  end
end

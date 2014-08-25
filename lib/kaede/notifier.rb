# coding: utf-8
require 'kaede'
require 'fluent-logger'

module Kaede
  class Notifier
    def initialize
      if Kaede.config.fluent_host && Kaede.config.fluent_port
        @fluent_logger = Fluent::Logger::FluentLogger.new(
          Kaede.config.fluent_tag_prefix,
          host: Kaede.config.fluent_host,
          port: Kaede.config.fluent_port,
        )
      else
        @fluent_logger = nil
      end
    end

    def notify_before_record(program)
      log(:before_record, message: "#{format_title(program)}を録画する")
    end

    def notify_after_record(program)
      message = sprintf(
        "%sを録画した。ファイルサイズ約%.2fGB。残り約%dGB\n",
        format_title(program),
        ts_filesize(program),
        available_disk,
      )
      log(:after_record, message: message)
    end

    def notify_exception(exception, program)
      log(:exception, message: "#{program.title}(PID #{program.pid}) の録画中に #{exception.class} で失敗した……")
    end

    def notify_duration_error(program, got_duration)
      log(:duration_error, message: sprintf('%s (PID:%d) の長さが%g秒しか無いようだが……', format_title(program), program.pid, got_duration))
    end

    def notify_redo_error(program)
      log(:redo_error, message: "再実行にも失敗した…… (PID:#{program.pid})")
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

    def log(tag, attributes)
      return unless @fluent_logger
      @fluent_logger.post(tag, attributes)
    end
  end
end

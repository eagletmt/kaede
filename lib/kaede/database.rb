require 'forwardable'
require 'sequel'
require 'kaede/channel'
require 'kaede/program'

module Kaede
  class Database
    extend Forwardable
    def_delegators :@db, :transaction

    def initialize(path)
      @db = Sequel.connect(path)
      prepare_tables
    end

    def prepare_tables
      @db.create_table?(:channels) do
        primary_key :id
        String :name, size: 255, null: false, unique: true
        Integer :for_recorder, null: false, unique: true
        Integer :for_syoboi, null: false, unique: true
      end
      @db.create_table?(:programs) do
        primary_key :pid
        Integer :tid, null: false
        DateTime :start_time, null: false
        DateTime :end_time, null: false
        foreign_key :channel_id, :channels
        String :count, size: 16, null: false
        Integer :start_offset, null: false
        String :subtitle, size: 255
        String :title, size: 255
        String :comment, size: 255
      end
      @db.create_table?(:jobs) do
        foreign_key :pid, :programs, primary_key: true
        DateTime :enqueued_at, null: false
        DateTime :finished_at
        DateTime :created_at, null: false
      end
      @db.create_table?(:tracking_titles) do
        Integer :tid, primary_key: true
        DateTime :created_at, null: false
      end
    end
    private :prepare_tables

    DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'

    def to_db_datetime(time)
      time.utc.strftime(DATETIME_FORMAT)
    end

    def from_db_datetime(str)
      Time.parse("#{str} UTC").localtime
    end

    def current_timestamp
      to_db_datetime(Time.now)
    end
    private :current_timestamp

    def get_jobs
      @db.execute('SELECT pid, enqueued_at FROM jobs WHERE finished_at IS NULL AND enqueued_at >= ? ORDER BY enqueued_at', [current_timestamp]).map do |pid, enqueued_at|
        { pid: pid, enqueued_at: from_db_datetime(enqueued_at) }
      end
    end

    def update_job(pid, enqueued_at)
      @db.execute('INSERT OR REPLACE INTO jobs (pid, enqueued_at, created_at) VALUES (?, ?, ?)', [pid, to_db_datetime(enqueued_at), current_timestamp])
    end

    def delete_job(pid)
      @db.execute('DELETE FROM jobs WHERE pid = ?', pid)
    end

    def get_program(pid)
      get_programs([pid])[pid]
    end

    def get_programs(pids)
      rows = @db.execute(<<-SQL)
SELECT pid, tid, start_time, end_time, channels.name, for_syoboi, for_recorder, count, start_offset, subtitle, title, comment
FROM programs
INNER JOIN channels ON programs.channel_id = channels.id
WHERE programs.pid IN (#{pids.join(', ')})
      SQL
      programs = {}
      rows.each do |row|
        program = Program.new(*row)
        program.start_time = from_db_datetime(program.start_time)
        program.end_time = from_db_datetime(program.end_time)
        programs[program.pid] = program
      end
      programs
    end

    def mark_finished(pid)
      @db.execute('UPDATE jobs SET finished_at = ? WHERE pid = ?', [current_timestamp, pid])
    end

    def get_channels
      @db.execute('SELECT * FROM channels').map do |row|
        Channel.new(*row)
      end
    end

    def add_channel(channel)
      @db.execute('INSERT INTO channels (name, for_recorder, for_syoboi) VALUES (?, ?, ?)', [channel.name, channel.for_recorder, channel.for_syoboi])
    end

    def update_program(program, channel)
      row = [
        program.pid,
        program.tid,
        to_db_datetime(program.start_time),
        to_db_datetime(program.end_time),
        channel.id,
        program.count,
        program.start_offset,
        program.subtitle,
        program.title,
        program.comment,
      ]
      @db.execute(<<-SQL, row)
INSERT INTO programs (pid, tid, start_time, end_time, channel_id, count, start_offset, subtitle, title, comment)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
    end

    def add_tracking_title(tid)
      @db.execute('INSERT INTO tracking_titles (tid, created_at) VALUES (?, ?)', [tid, current_timestamp])
    end

    def get_tracking_titles
      @db.execute('SELECT tid FROM tracking_titles').map do |row|
        row[0]
      end
    end
  end
end

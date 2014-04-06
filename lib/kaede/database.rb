require 'forwardable'
require 'sqlite3'
require 'kaede/channel'
require 'kaede/program'

module Kaede
  class Database
    extend Forwardable
    def_delegators :@db, :transaction

    def initialize(path)
      @db = SQLite3::Database.new(path.to_s)
      @db.send(:set_boolean_pragma, 'foreign_keys', true)
      prepare_tables
    end

    def prepare_tables
      @db.execute_batch <<-SQL
CREATE TABLE IF NOT EXISTS channels (
  id integer PRIMARY KEY AUTOINCREMENT,
  name varchar(255) NOT NULL UNIQUE,
  for_recorder integer NOT NULL UNIQUE,
  for_syoboi integer NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS programs (
  pid integer PRIMARY KEY ON CONFLICT REPLACE,
  tid integer NOT NULL,
  start_time datetime NOT NULL,
  end_time datetime NOT NULL,
  channel_id integer NOT NULL,
  count varchar(16),
  start_offset integer NOT NULL,
  subtitle varchar(255),
  title varchar(255),
  comment varchar(255),
  FOREIGN KEY(channel_id) REFERENCES channels(id)
);
CREATE TABLE IF NOT EXISTS jobs (
  id integer PRIMARY KEY AUTOINCREMENT,
  pid integer NOT NULL UNIQUE,
  enqueued_at datetime NOT NULL,
  finished_at datetime,
  created_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY(pid) REFERENCES programs(pid)
);
CREATE TABLE IF NOT EXISTS tracking_titles (
  tid integer NOT NULL UNIQUE,
  created_at datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
);
      SQL
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
      @db.execute('SELECT id, pid, enqueued_at FROM jobs WHERE finished_at IS NULL AND enqueued_at >= ? ORDER BY enqueued_at', [current_timestamp]).map do |id, pid, enqueued_at|
        { id: id, pid: pid, enqueued_at: from_db_datetime(enqueued_at) }
      end
    end

    def add_job(pid, enqueued_at)
      @db.execute('INSERT INTO jobs (pid, enqueued_at, created_at) VALUES (?, ?, ?)', [pid, to_db_datetime(enqueued_at), current_timestamp])
    end

    def delete_job(id)
      @db.execute('DELETE FROM jobs WHERE id = ?', id)
    end

    def get_program_from_job_id(id)
      get_programs_from_job_ids([id])[id]
    end

    def get_programs_from_job_ids(ids)
      rows = @db.execute(<<-SQL)
SELECT jobs.id, jobs.pid, tid, start_time, end_time, channels.name, for_syoboi, for_recorder, count, start_offset, subtitle, title, comment
FROM jobs
INNER JOIN programs ON jobs.pid = programs.pid
INNER JOIN channels ON programs.channel_id = channels.id
WHERE jobs.id IN (#{ids.join(', ')})
      SQL
      programs = {}
      rows.each do |row|
        job_id = row.shift
        program = Program.new(*row)
        program.start_time = from_db_datetime(program.start_time)
        program.end_time = from_db_datetime(program.end_time)
        programs[job_id] = program
      end
      programs
    end

    def mark_finished(id)
      @db.execute('UPDATE jobs SET finished_at = ? WHERE id = ?', [current_timestamp, id])
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

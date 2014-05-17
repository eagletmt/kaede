require 'spec_helper'

require 'tempfile'
require 'timeout'
require 'kaede'
require 'kaede/database'
require 'kaede/recorder'
require 'kaede/scheduler'
require 'kaede/dbus'

describe Kaede::Scheduler do
  let(:db_file) { Tempfile.open('kaede.db') }
  let(:db) { Kaede::Database.new(db_file.path) }

  describe '.start' do
    let(:program) { Kaede::Program.new(1234, 5678, Time.now, Time.now + 30, nil, 19, 9, '5.5', 0, 'sub', 'title', '') }

    before do
      db.add_channel(Kaede::Channel.new(nil, 'MX', 9, 19))
      channel = db.get_channels.first
      db.update_program(program, channel)
      db.update_job(program.pid, Time.now + 5)
    end

    it 'works' do
      q = Queue.new
      allow_any_instance_of(Kaede::Recorder).to receive(:record) { |recorder, db, pid|
        q.push(pid)
      }
      described_class.setup(db)
      expect(db.get_jobs.size).to eq(1)
      thread = Thread.start do
        described_class.start
      end

      begin
        Timeout.timeout(10) do
          expect(q.pop).to eq(program.pid)
        end
      ensure
        described_class.fire_stop
        thread.join
      end
      expect(db.get_jobs.size).to eq(0)
    end
  end
end

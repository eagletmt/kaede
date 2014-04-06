require 'spec_helper'

require 'tempfile'
require 'timeout'
require 'kaede'
require 'kaede/database'
require 'kaede/recorder'
require 'kaede/scheduler'

describe Kaede::Scheduler do
  let(:db_file) { Tempfile.open('kaede.db') }
  let(:db) { Kaede::Database.new(db_file.path) }

  describe '.start' do
    let(:program) { Kaede::Program.new(1234, 5678, Time.now, Time.now + 30, nil, 19, 9, '5.5', 0, 'sub', 'title', '') }

    before do
      db.add_channel(Kaede::Channel.new(nil, 'MX', 9, 19))
      channel = db.get_channels.first
      db.update_program(program, channel)
      db.add_job(program.pid, Time.now + 5)
    end

    it 'works' do
      r, w = IO.pipe
      allow_any_instance_of(Kaede::Recorder).to receive(:record) { |recorder, db, job_id|
        program = db.get_program_from_job_id(job_id)
        puts "Record #{program.pid}"
      }
      pid = fork do
        r.close
        $stdout.reopen(w)
        described_class.setup(db)
        described_class.start
      end
      w.close

      expect(db.get_jobs.size).to eq(1)
      begin
        Timeout.timeout(10) do
          while s = r.gets.chomp
            if s =~ /\ARecord (\d+)\z/
              expect($1.to_i).to eq(program.pid)
              break
            end
          end
        end
      ensure
        Process.kill(:INT, pid)
        Process.waitpid(pid)
      end
      expect(db.get_jobs.size).to eq(0)
    end
  end
end

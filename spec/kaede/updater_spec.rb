require 'spec_helper'
require 'kaede/channel'
require 'kaede/database'
require 'kaede/syoboi_calendar'
require 'kaede/updater'

describe Kaede::Updater do
  let(:db) { Kaede::Database.new(':memory:') }
  let(:syobocal) { Kaede::SyoboiCalendar.new }
  let(:updater) { described_class.new(db, syobocal) }

  describe '#update' do
    let(:channel) { Kaede::Channel.new(nil, 'MX', 9, 19) }
    let(:tracking_tid) { 3225 }

    let(:expected_pid) { 279855 }
    let(:expected_enqueued_at) { Time.local(2014, 3, 6, 21, 59, 45) }

    around do |example|
      Timecop.travel(Time.local(2014, 3, 5, 18, 0)) do
        example.run
      end
    end

    before do
      db.add_channel(channel)
      db.add_tracking_title(tracking_tid)

      allow(updater).to receive(:reload_scheduler)
      @orig_stderr = $stderr
      $stderr = open(File::NULL, 'w')
    end

    after do
      $stderr = @orig_stderr
    end

    it 'inserts new jobs' do
      VCR.use_cassette('cal_chk/days7') do
        expect { updater.update }.to output(/Insert job for #{expected_pid}/).to_stdout
      end

      jobs = db.get_jobs
      expect(jobs.size).to eq(1)
      job = jobs[0]
      expect(job[:pid]).to eq(expected_pid)
      expect(job[:enqueued_at]).to eq(expected_enqueued_at)
    end
  end
end

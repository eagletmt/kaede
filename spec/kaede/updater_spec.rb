require 'spec_helper'
require 'kaede/channel'
require 'kaede/database'
require 'kaede/syoboi_calendar'
require 'kaede/updater'

describe Kaede::Updater do
  let(:db) { Kaede::Database.new(DatabaseHelper.database_url) }
  let(:syobocal) { Kaede::SyoboiCalendar.new }
  let(:updater) { described_class.new(db, syobocal) }

  before do
    db.prepare_tables
  end

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
        updater.update
      end

      jobs = db.get_jobs
      expect(jobs.size).to eq(1)
      job = jobs[0]
      expect(job[:pid]).to eq(expected_pid)
      expect(job[:enqueued_at]).to eq(expected_enqueued_at)
    end

    it 'updates existing job' do
      dummy_time = Time.local(2014, 3, 6, 20, 29, 45)

      VCR.use_cassette('cal_chk/days7') do
        updater.update
      end
      db.update_job(expected_pid, dummy_time)
      job1 = db.get_jobs[0]
      expect(job1[:enqueued_at]).to eq(dummy_time)
      VCR.use_cassette('cal_chk/days7') do
        updater.update
      end
      job2 = db.get_jobs[0]
      expect(job2[:enqueued_at]).to eq(expected_enqueued_at)
      expect(job2[:pid]).to eq(job1[:pid])
    end
  end
end

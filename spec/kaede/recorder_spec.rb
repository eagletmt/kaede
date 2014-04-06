require 'spec_helper'

require 'kaede'
require 'kaede/database'
require 'kaede/recorder'
require 'kaede/updater'

describe Kaede::Recorder do
  let(:recorder) { described_class.new }
  let(:db) { Kaede::Database.new(':memory:') }
  let(:job) { db.get_jobs.first }
  let(:program) { db.get_program_from_job_id(job[:id]) }
  let(:duration) { 30 }

  let(:fname) { '5678_1234' }
  let(:formatted_fname) { '5678_1234 title #6 sub (comment) at MX' }
  let(:record_dir) { @tmpdir.join('record').tap(&:mkpath) }
  let(:record_path) { record_dir.join("#{fname}.ts") }
  let(:cache_dir) { @tmpdir.join('cache').tap(&:mkpath) }
  let(:cache_path) { cache_dir.join("#{fname}.cache.ts") }
  let(:cache_ass_path) { cache_dir.join("#{fname}.raw.ass") }
  let(:cabinet_dir) { @tmpdir.join('cabinet').tap(&:mkpath) }
  let(:cabinet_path) { cabinet_dir.join("#{formatted_fname}.ts") }
  let(:cabinet_ass_path) { cabinet_dir.join("#{formatted_fname}.raw.ass") }

  before do
    db.add_channel(Kaede::Channel.new(nil, 'MX', 9, 19))
    channel = db.get_channels.first
    program = Kaede::Program.new(1234, 5678, Time.now, Time.now + duration, nil, 19, 9, '6', 0, 'sub', 'title', 'comment')
    db.update_program(program, channel)
    db.add_job(program.pid, Time.now + 5)

    Kaede.configure do |config|
      config.redis = double('redis')
      tools = @topdir.join('tools')
      config.recpt1 = tools.join('recpt1')
      config.b25 = tools.join('b25')
      config.assdumper = tools.join('assdumper')
      config.statvfs = tools.join('statvfs')
      config.clean_ts = tools.join('clean-ts')
      config.record_dir = record_dir
      config.cache_dir = cache_dir
      config.cabinet_dir = cabinet_dir
    end
  end

  describe '#record' do
    it 'calls before_record -> do_record -> after_record' do
      expect(recorder).to receive(:before_record).ordered.with(program)
      expect(recorder).to receive(:do_record).ordered.with(program, instance_of(Pathname), instance_of(Fixnum))
      expect(recorder).to receive(:after_record).ordered.with(program, instance_of(Pathname))

      expect { recorder.record(db, job[:id]) }.to output(/Start #{job[:id]}.*Done #{job[:id]}/m).to_stdout
    end
  end

  describe '#before_record' do
    it 'tweets' do
      expect(recorder).to receive(:tweet).with(/title #6 sub/)
      recorder.before_record(program)
    end
  end

  describe '#after_record' do
    before do
      record_path.open('w') {}
      cache_path.open('w') {}
      cache_ass_path.open('w') { |f| f.puts 'ass' }

      allow(Kaede.config.redis).to receive(:rpush)
      @orig_stdout = $stdout
      $stdout = open(File::NULL, 'w')
    end

    after do
      $stdout = @orig_stdout
    end

    it 'tweets' do
      expect(recorder).to receive(:tweet).with(/title #6 sub/)
      recorder.after_record(program, record_path)
    end

    it 'cleans cached TS' do
      expect(cache_path).to be_exist
      expect(cabinet_path).to_not be_exist

      recorder.after_record(program, record_path)

      expect(cache_path).to_not be_exist
      expect(cabinet_path).to be_exist
    end

    it 'moves ass' do
      expect(cache_ass_path).to be_exist
      expect(cabinet_ass_path).to_not be_exist

      recorder.after_record(program, record_path)

      expect(cache_ass_path).to_not be_exist
      expect(cabinet_ass_path).to be_exist
    end

    it 'enqueues to redis' do
      expect(Kaede.config.redis).to receive(:rpush).with(Kaede.config.redis_queue, formatted_fname)

      recorder.after_record(program, record_path)
    end

    context 'with empty ass' do
      before do
        cache_ass_path.open('w') {}
      end

      it 'removes ass' do
        expect(cache_ass_path).to be_exist
        expect(cabinet_ass_path).to_not be_exist

        recorder.after_record(program, record_path)

        expect(cache_ass_path).to_not be_exist
        expect(cabinet_ass_path).to_not be_exist
      end
    end
  end

  describe '#do_record' do

    it 'creates raw TS in record dir' do
      expect(record_path).to_not be_exist
      recorder.do_record(program, record_path, duration)
      expect(record_path).to be_exist
      expect(record_path.read.chomp).to eq("#{program.channel_for_recorder} #{duration}")
    end

    it 'creates b25-decoded TS in cache dir' do
      expect(cache_path).to_not be_exist
      recorder.do_record(program, record_path, duration)
      expect(cache_path).to be_exist
      expect(cache_path.read.chomp).to eq(record_path.read.chomp.reverse)
    end

    it 'creates ass in cache dir' do
      expect(cache_ass_path).to_not be_exist
      recorder.do_record(program, record_path, duration)
      expect(cache_ass_path).to be_exist
      expect(cache_ass_path.read.chomp).to eq(record_path.read.chomp.gsub('1', '2'))
    end
  end

  describe '#calculate_duration' do
    subject { recorder.calculate_duration(program) }

    it 'returns duration' do
      is_expected.to eq(duration - 10)
    end

    context 'with NHK (which has no CM)' do
      before do
        program.channel_name = 'NHK-G'
      end

      it 'has additional record time' do
        is_expected.to eq(duration + Kaede::Updater::JOB_TIME_GAP)
      end
    end

    context 'with MX on Sunday 22:00' do
      before do
        program.start_time = Time.local(2014, 4, 6, 22, 00)
        program.end_time = Time.local(2014, 4, 6, 22, 27)
      end

      it 'has 30min duration even if Syoboi Calendar says 27min' do
        is_expected.to eq(30*60 - 10)
      end
    end
  end
end

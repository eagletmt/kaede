require 'spec_helper'

require 'kaede'
require 'kaede/database'
require 'kaede/recorder'
require 'kaede/updater'

describe Kaede::Recorder do
  let(:notifier) { double('Notifier') }
  let(:recorder) { described_class.new(notifier) }
  let(:db) { Kaede::Database.new(':memory:') }
  let(:job) { db.get_jobs.first }
  let(:program) { db.get_program(job[:pid]) }
  let(:duration) { 30 }

  let(:formatted_fname) { '5678_1234 title #6 sub (comment) at MX' }
  let(:record_dir) { @tmpdir.join('record').tap(&:mkpath) }
  let(:record_path) { recorder.record_path(program) }
  let(:cache_dir) { @tmpdir.join('cache').tap(&:mkpath) }
  let(:cache_path) { recorder.cache_path(program) }
  let(:cache_ass_path) { recorder.cache_ass_path(program) }
  let(:cabinet_dir) { @tmpdir.join('cabinet').tap(&:mkpath) }
  let(:cabinet_path) { recorder.cabinet_path(program) }
  let(:cabinet_ass_path) { recorder.cabinet_ass_path(program) }

  before do
    db.add_channel(Kaede::Channel.new(nil, 'MX', 9, 19))
    channel = db.get_channels.first
    program = Kaede::Program.new(1234, 5678, Time.now, Time.now + duration, nil, 19, 9, '6', 0, 'sub', 'title', 'comment')
    db.update_program(program, channel)
    db.update_job(program.pid, Time.now + 5)

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
      expect(recorder).to receive(:do_record).ordered.with(program)
      expect(recorder).to receive(:after_record).ordered.with(program)

      expect { recorder.record(db, job[:pid]) }.to output(/Start #{job[:pid]}.*Done #{job[:pid]}/m).to_stdout
    end

    it 'notifies exception' do
      e = Class.new(Exception)
      expect(notifier).to receive(:notify_exception).with(e, program)
      allow(recorder).to receive(:before_record)
      allow(recorder).to receive(:do_record).and_raise(e)
      allow(recorder).to receive(:after_record)

      expect { recorder.record(db, job[:pid]) }.to raise_error(e)
    end
  end

  describe '#after_record' do
    before do
      record_path.open('w') {}
      cache_path.open('w') {}
      cache_ass_path.open('w') { |f| f.puts 'ass' }

      allow(Kaede.config.redis).to receive(:rpush)
      allow(notifier).to receive(:notify_after_record).with(program)
    end

    it 'calls Notifier#notify_after_record' do
      expect(notifier).to receive(:notify_after_record).with(program)
      recorder.after_record(program)
    end

    it 'cleans cached TS' do
      expect(cache_path).to be_exist
      expect(cabinet_path).to_not be_exist

      recorder.after_record(program)

      expect(cache_path).to_not be_exist
      expect(cabinet_path).to be_exist
    end

    it 'moves ass' do
      expect(cache_ass_path).to be_exist
      expect(cabinet_ass_path).to_not be_exist

      recorder.after_record(program)

      expect(cache_ass_path).to_not be_exist
      expect(cabinet_ass_path).to be_exist
    end

    it 'enqueues to redis' do
      expect(Kaede.config.redis).to receive(:rpush).with(Kaede.config.redis_queue, formatted_fname)

      recorder.after_record(program)
    end

    context 'with empty ass' do
      before do
        cache_ass_path.open('w') {}
      end

      it 'removes ass' do
        expect(cache_ass_path).to be_exist
        expect(cabinet_ass_path).to_not be_exist

        recorder.after_record(program)

        expect(cache_ass_path).to_not be_exist
        expect(cabinet_ass_path).to_not be_exist
      end
    end
  end

  describe '#do_record' do
    it 'creates raw TS in record dir' do
      expect(record_path).to_not be_exist
      recorder.do_record(program)
      expect(record_path).to be_exist
      expect(record_path.read.chomp).to eq("#{program.channel_for_recorder} #{duration - 10}")
    end

    it 'creates b25-decoded TS in cache dir' do
      expect(cache_path).to_not be_exist
      recorder.do_record(program)
      expect(cache_path).to be_exist
      expect(cache_path.read.chomp).to eq(record_path.read.chomp.reverse)
    end

    it 'creates ass in cache dir' do
      expect(cache_ass_path).to_not be_exist
      recorder.do_record(program)
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

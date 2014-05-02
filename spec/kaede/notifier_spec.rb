require 'spec_helper'

require 'kaede/notifier'
require 'kaede/program'

describe Kaede::Notifier do
  let(:notifier) { described_class.new }
  let(:duration) { 30 }
  let(:program) { Kaede::Program.new(1234, 5678, Time.now, Time.now + duration, nil, 19, 9, '6', 0, 'sub', 'title', 'comment') }

  describe '#notify_before_record' do
    it 'tweets' do
      expect(notifier).to receive(:tweet).with(/title #6 sub/)
      notifier.notify_before_record(program)
    end
  end

  describe '#notify_after_record' do
    before do
      Kaede.configure do |config|
        config.record_dir = @tmpdir.join('record').tap(&:mkpath)
        tools = @topdir.join('tools')
        config.statvfs = tools.join('statvfs')
      end

      notifier.record_path(program).open('w') {}
    end

    it 'tweets' do
      expect(notifier).to receive(:tweet).with(/title #6 sub.*0\.00GB/)
      notifier.notify_after_record(program)
    end
  end
end

require 'spec_helper'
require 'kaede/syoboi_calendar'

describe Kaede::SyoboiCalendar do
  let(:client) { described_class.new }

  describe '#cal_chk' do
    it 'works' do
      VCR.use_cassette('cal_chk/all') do
        programs = client.cal_chk
        programs.each do |program|
          program.members.each do |attr|
            next if [:channel_name, :channel_for_recorder].include?(attr)
            expect(program[attr]).to_not be_nil
          end
        end
      end
    end
  end
end

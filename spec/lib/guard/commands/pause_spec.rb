require 'spec_helper'

describe 'Guard::Interactor::PAUSE' do

  describe '#perform' do
    let!(:guard) { ::Guard.setup }

    it 'pauses Guard' do
      expect(::Guard).to receive(:pause)
      Pry.run_command 'pause'
      guard.send(:_process_queue)
    end
  end

end

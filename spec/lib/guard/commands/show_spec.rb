require 'spec_helper'

describe 'Guard::Interactor::SHOW' do

  describe '#perform' do
    let!(:guard) { ::Guard.setup }
    let(:dsl_describer) { double(:describer) }

    before do
      allow(::Guard::DslDescriber).to receive(:new) { dsl_describer }
    end

    it 'outputs the DSL description' do
      expect(dsl_describer).to receive(:show)
      Pry.run_command 'show'
      guard.send(:_process_queue)
    end
  end

end

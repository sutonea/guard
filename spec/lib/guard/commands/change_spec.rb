require 'spec_helper'

describe 'Guard::Interactor::CHANGE' do

  before do
    ::Guard.setup
    allow(Guard.runner).to receive(:run_on_changes)
    allow(Pry.output).to receive(:puts)
  end

  describe '#perform' do
    context 'with a file' do
      it 'runs the :run_on_changes action with the given scope' do
        expect(::Guard).to receive(:async_queue_add).with(modified: ['foo'], added: [], removed: [])
        Pry.run_command 'change foo'
      end
    end

    context 'with multiple files' do
      it 'runs the :run_on_changes action with the given scope' do
        expect(::Guard).to receive(:async_queue_add).with(modified: ['foo', 'bar', 'baz'], added: [], removed: [])
        Pry.run_command 'change foo bar baz'
      end
    end

    context 'without a file' do
      it 'does not run the :run_on_changes action' do
        expect(::Guard).to_not receive(:async_queue_add)
        Pry.run_command 'change'
      end
    end
  end

end

require 'spec_helper'
require 'guard/plugin'

describe Guard::Commander do
  before do
    allow(::Guard).to receive(:_interactor_loop) { }
  end

  describe '.start' do
    before do
      ::Guard.instance_variable_set('@watchdirs', [])
      allow(::Guard).to receive(:setup)
      allow(::Guard).to receive(:listener).and_return(double('listener', start: true))
      allow(::Guard).to receive(:runner).and_return(double('runner', run: true))
    end

    context 'Guard has not been setuped' do
      before { allow(::Guard).to receive(:running).and_return(false) }

      it "setup Guard" do
        expect(::Guard).to receive(:setup).with(foo: 'bar')

        ::Guard.start(foo: 'bar')
      end
    end

    it "displays an info message" do
      ::Guard.instance_variable_set('@watchdirs', ['/foo/bar'])
      expect(::Guard::UI).to receive(:info).with("Guard is now watching at '/foo/bar'")

      ::Guard.start
    end

    it "tell the runner to run the :start task" do
      expect(::Guard.runner).to receive(:run).with(:start)

      ::Guard.start
    end

    it "start the listener" do
      expect(::Guard.listener).to receive(:start)

      ::Guard.start
    end
  end

  describe '.stop' do
    before do
      allow(::Guard).to receive(:setup)
      allow(::Guard).to receive(:listener).and_return(double('listener', stop: true))
      allow(::Guard).to receive(:runner).and_return(double('runner', run: true))
    end

    context 'Guard has not been setuped' do
      before { allow(::Guard).to receive(:running).and_return(false) }

      it "setup Guard" do
        expect(::Guard).to receive(:setup)

        ::Guard.stop
      end
    end

    it "turns the notifier off" do
      expect(::Guard::Notifier).to receive(:turn_off)

      ::Guard.stop
    end

    it "tell the runner to run the :stop task" do
      expect(::Guard.runner).to receive(:run).with(:stop)

      ::Guard.stop
    end

    it "stops the listener" do
      expect(::Guard.listener).to receive(:stop)

      ::Guard.stop
    end

    it "sets the running state to false" do
      ::Guard.running = true
      ::Guard.stop
      expect(::Guard.running).to be_falsey
    end
  end

  describe '.reload' do
    let(:runner) { double(run: true) }
    let(:group) { ::Guard::Group.new('frontend') }
    subject { ::Guard.setup }

    before do
      allow(::Guard).to receive(:runner) { runner }
      allow(::Guard).to receive(:scope) { {} }
      allow(::Guard::UI).to receive(:info)
      allow(::Guard::UI).to receive(:clear)
    end

    context 'Guard has not been setuped' do
      before { allow(::Guard).to receive(:running).and_return(false) }

      it "setup Guard" do
        expect(::Guard).to receive(:setup)

        ::Guard.reload
      end
    end

    it 'clears the screen' do
      expect(::Guard::UI).to receive(:clear)

      subject.reload
    end

    context 'with a given scope' do
      it 'does not re-evaluate the Guardfile' do
        expect_any_instance_of(::Guard::Guardfile::Evaluator)
          .to_not receive(:reevaluate_guardfile)

        subject.reload({ groups: [group] })
      end

      it 'reloads Guard' do
        expect(runner).to receive(:run).with(:reload, { groups: [group] })

        subject.reload({ groups: [group] })
      end
    end

    context 'with an empty scope' do
      it 'does re-evaluate the Guardfile' do
        expect_any_instance_of(::Guard::Guardfile::Evaluator)
          .to receive(:reevaluate_guardfile)

        subject.reload
      end

      it 'does not reload Guard' do
        expect(runner).to_not receive(:run).with(:reload, {})

        subject.reload
      end
    end
  end

  describe '.run_all' do
    let(:runner) { double(run: true) }
    let(:group) { ::Guard::Group.new('frontend') }
    subject { ::Guard.setup }

    before do
      allow(::Guard).to receive(:runner) { runner }
      allow(::Guard::UI).to receive(:action_with_scopes)
      allow(::Guard::UI).to receive(:clear)
    end

    context 'Guard has not been setuped' do
      before { allow(::Guard).to receive(:running).and_return(false) }

      it "setup Guard" do
        expect(::Guard).to receive(:setup)

        ::Guard.run_all
      end
    end

    context 'with a given scope' do
      it 'runs all with the scope' do
        expect(runner).to receive(:run).with(:run_all, { groups: [group] })

        subject.run_all({ groups: [group] })
      end
    end

    context 'with an empty scope' do
      it 'runs all' do
        expect(runner).to receive(:run).with(:run_all, {})

        subject.run_all
      end
    end
  end

  describe '.pause' do
    subject { ::Guard.setup }
    let!(:listener) { double(:listener) }
    before do
      allow(subject).to receive(:listener) { listener }
    end

    context 'when unpaused' do

      before do
        allow(listener).to receive(:paused?) { false }
      end

      [:toggle, nil, :paused].each do |mode|
        context "with #{mode.inspect}" do
          it "pauses" do
            expect(listener).to receive(:pause)
            subject.pause(mode)
          end
        end
      end

      context 'with :unpaused' do
        it "does nothing" do
          expect(listener).to_not receive(:unpause)
          expect(listener).to_not receive(:pause)
          subject.pause(:unpaused)
        end
      end

      context 'with invalid parameter' do
        it "raises an ArgumentError" do
          expect { subject.pause(:invalid) }.to raise_error(ArgumentError, 'invalid mode: :invalid')
        end
      end
    end

    context 'when already paused' do
      let!(:listener) { ::Guard.listener }

      before do
        allow(::Guard.listener).to receive(:paused?) { true }
      end

      [:toggle, nil, :unpaused].each do |mode|
        context "with #{mode.inspect}" do
          it "unpauses" do
            expect(listener).to receive(:unpause)
            subject.pause(mode)
          end
        end
      end

      context 'with :paused' do
        it "does nothing" do
          expect(listener).to_not receive(:unpause)
          expect(listener).to_not receive(:pause)
          subject.pause(:paused)
        end
      end

      context 'with invalid parameter' do
        it "raises an ArgumentError" do
          expect { subject.pause(:invalid) }.to raise_error(ArgumentError, 'invalid mode: :invalid')
        end
      end
    end

  end
end

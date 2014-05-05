module Guard
  class Interactor

    CHANGE = Pry::CommandSet.new do
      create_command 'change' do

        group 'Guard'
        description 'Trigger a file change.'

        banner <<-BANNER
          Usage: change <file> <other_file>

          Pass the given files to the Guard plugin `run_on_changes` action.
        BANNER

        def process(*entries)
          _, files = ::Guard::Interactor.convert_scope(entries)

          if files.empty?
            output.puts 'Please specify a file.'
          else
            ::Guard.async_queue_add(modified: files, added: [], removed: [])
          end
        end

      end
    end

  end
end

Pry.commands.import ::Guard::Interactor::CHANGE

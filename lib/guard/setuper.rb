require 'thread'
require 'listen'
require 'guard/options'

module Guard

  module Setuper

    DEFAULT_OPTIONS = {
      clear: false,
      notify: true,
      debug: false,
      group: [],
      plugin: [],
      watchdir: nil,
      guardfile: nil,
      no_interactions: false,
      no_bundler_warning: false,
      show_deprecations: false,
      latency: nil,
      force_polling: false,
      wait_for_delay: nil,
      listen_on: nil
    }
    DEFAULT_GROUPS = [:default]

    # Initializes the Guard singleton:
    #
    # * Initialize the internal Guard state;
    # * Create the interactor
    # * Select and initialize the file change listener.
    #
    # @option options [Boolean] clear if auto clear the UI should be done
    # @option options [Boolean] notify if system notifications should be shown
    # @option options [Boolean] debug if debug output should be shown
    # @option options [Array<String>] group the list of groups to start
    # @option options [Array<String>] watchdir the directories to watch
    # @option options [String] guardfile the path to the Guardfile
    #
    # @return [Guard] the Guard singleton
    #
    def setup(opts = {})
      @options    = nil
      @evaluator  = nil
      @interactor = nil
      @running   = true
      @opts      = opts
      @watchdirs = [Dir.pwd]
      @runner    = ::Guard::Runner.new
      @queue = Queue.new

      if options[:watchdir]
        # Ensure we have an array
        @watchdirs = Array(options[:watchdir]).map { |dir| File.expand_path dir }
      end

      ::Guard::UI.clear(force: true)
      _setup_debug if options[:debug]
      _setup_listener
      _setup_signal_traps

      reset_groups
      reset_plugins
      reset_scope

      evaluate_guardfile

      setup_scope(groups: options[:group], plugins: options[:plugin])

      _setup_notifier

      self
    end

    # Lazy initializer for Guard's options hash
    #
    def options
      @options ||= ::Guard::Options.new(@opts, DEFAULT_OPTIONS)
    end

    # Lazy initializer for Guardfile evaluator
    #
    def evaluator
      @evaluator ||= ::Guard::Guardfile::Evaluator.new(@opts || {})
    end

    # Lazy initializer the interactor unless the user has specified not to.
    #
    def interactor
      non_interactive = options[:no_interactions] || !::Guard::Interactor.enabled
      @interactor ||= ::Guard::Interactor.new(non_interactive)
    end

    # Clear Guard's options hash
    #
    def clear_options
      @options = nil
    end

    # Initializes the groups array with the default group(s).
    #
    # @see DEFAULT_GROUPS
    #
    def reset_groups
      @groups = DEFAULT_GROUPS.map { |name| Group.new(name) }
    end

    # Initializes the plugins array to an empty array.
    #
    # @see Guard.plugins
    #
    def reset_plugins
      @plugins = []
    end

    # Initializes the scope hash to `{ groups: [], plugins: [] }`.
    #
    # @see Guard.setup_scope
    #
    def reset_scope
      @scope = { groups: [], plugins: [] }
    end

    # Stores the scopes defined by the user via the `--group` / `-g` option (to run
    # only a specific group) or the `--plugin` / `-P` option (to run only a
    # specific plugin).
    #
    # @see CLI#start
    # @see Dsl#scope
    #
    def setup_scope(new_scope)
      if new_scope[:groups] && new_scope[:groups].any?
        scope[:groups]  = new_scope[:groups].map { |group| ::Guard.add_group(group) }
      end

      if new_scope[:plugins] && new_scope[:plugins].any?
        scope[:plugins] = new_scope[:plugins].map { |plugin| ::Guard.plugin(plugin) }
      end
    end

    # Evaluates the Guardfile content. It displays an error message if no
    # Guard plugins are instantiated after the Guardfile evaluation.
    #
    # @see Guard::Guardfile::Evaluator#evaluate_guardfile
    #
    def evaluate_guardfile
      evaluator.evaluate_guardfile
      ::Guard::UI.error 'No plugins found in Guardfile, please add at least one.' if plugins.empty?
    end

    # Asynchronously trigger changes
    #
    # Currently supported args:
    #
    #   old style hash: {modified: ['foo'], added: ['bar'], removed: []}
    #
    #   new style signals with args: [:guard_pause, :unpaused ]
    #
    def async_queue_add(changes)
      @queue << changes

      # Putting interactor in background puts guard into foreground
      # so it can handle change notifications
      Thread.new { interactor.background }
    end

    def pending_changes?
      ! @queue.empty?
    end

    private

    # Sets up various debug behaviors:
    #
    # * Abort threads on exception;
    # * Set the logging level to `:debug`;
    # * Modify the system and ` methods to log themselves before being executed
    #
    # @see #_debug_command_execution
    #
    def _setup_debug
      Thread.abort_on_exception = true
      ::Guard::UI.options[:level] = :debug
      _debug_command_execution
    end

    # Initializes the listener and registers a callback for changes.
    #
    def _setup_listener
      listener_callback = lambda do |modified, added, removed|
        all_changes = { modified: modified.dup, added: added.dup, removed: removed.dup }

        # Convert to relative paths (respective to the watchdir it came from)
        # TODO: this should be Listen's responsibility
        @watchdirs.each do |watchdir|
          all_changes.each do |type, paths|
            paths.each do |path|
              if path.start_with? watchdir
                path.sub! "#{watchdir}#{File::SEPARATOR}", ''
              end
            end
          end
        end

        async_queue_add(all_changes) if _relevant_changes?(all_changes)
      end

      if options[:listen_on]
        @listener = Listen.on(options[:listen_on], &listener_callback)
      else
        listener_options = {}
        [:latency, :force_polling, :wait_for_delay].each do |option|
          listener_options[option] = options[option] if options[option]
        end
        listen_args = @watchdirs + [listener_options]
        @listener = Listen.to(*listen_args, &listener_callback)
      end
    end

    # Process the change queue, running tasks within the main Guard thread
    def _process_queue
      all_changes = {modified: [], added: [], removed: []}
      all_actions = []

      while pending_changes?
        item = @queue.pop
        if item.first.is_a?(Symbol)
          all_actions << item
        else
          item.each do |key, value|
            all_changes[key] += value
          end
        end
      end

      #TODO: use respond_to? and call
      all_actions.each do |action_args|
        action, args = action_args
        case action
        when :guard_pause
          pause args
        when :guard_run_all
          run_all args
        when :guard_reload
          reload args
        when :guard_show
          ::Guard::DslDescriber.new(::Guard.options).show
        else
          raise "Unknown action: #{action.inspect}"
        end
      end

      runner.run_on_changes(all_changes[:modified], all_changes[:added], all_changes[:removed])
    end

    # Sets up traps to catch signals used to control Guard.
    #
    # Currently two signals are caught:
    # - `USR1` which pauses listening to changes.
    # - `USR2` which resumes listening to changes.
    # - 'INT' which is delegated to Pry if active, otherwise stops Guard.
    #
    def _setup_signal_traps
      unless defined?(JRUBY_VERSION)
        if Signal.list.keys.include?('USR1')
          Signal.trap('USR1') { async_queue_add([:guard_pause, :paused]) }
        end

        if Signal.list.keys.include?('USR2')
          Signal.trap('USR2') { async_queue_add([:guard_pause, :unpaused]) }
        end

        if Signal.list.keys.include?('INT')
          Signal.trap('INT') do
            interactor.handle_interrupt
          end
        end
      end
    end

    # Enables or disables the notifier based on user's configurations.
    #
    def _setup_notifier
      if options[:notify] && ENV['GUARD_NOTIFY'] != 'false'
        ::Guard::Notifier.turn_on
      else
        ::Guard::Notifier.turn_off
      end
    end

    # Adds a command logger in debug mode. This wraps common command
    # execution functions and logs the executed command before execution.
    #
    def _debug_command_execution
      Kernel.send(:alias_method, :original_system, :system)
      Kernel.send(:define_method, :system) do |command, *args|
        ::Guard::UI.debug "Command execution: #{ command } #{ args.join(' ') }"
        Kernel.send :original_system, command, *args
      end

      Kernel.send(:alias_method, :original_backtick, :'`')
      Kernel.send(:define_method, :'`') do |command|
        ::Guard::UI.debug "Command execution: #{ command }"
        Kernel.send :original_backtick, command
      end
    end

    # Check if any of the changes are actually watched for
    #
    # NOTE: this is called from the listen thread - be careful to not
    # modify any state
    #
    # TODO: move this to watcher class?
    #
    def _relevant_changes?(changes)
      #TODO: make a Guardfile reloader "plugin" instead of a special case
      return true if ::Guard::Watcher.match_guardfile?(changes[:modified])

      #TODO: ignoring irrelevant files should be Listen's responsibility
      all_files = changes.values.flatten(1)
      runner.send(:_scoped_plugins) do |guard|
        return true if ::Guard::Watcher.match_files?([guard], all_files)
      end
      false
    end

  end
end

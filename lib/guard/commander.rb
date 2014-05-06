module Guard

  module Commander

    # Start Guard by evaluating the `Guardfile`, initializing declared Guard plugins
    # and starting the available file change listener.
    # Main method for Guard that is called from the CLI when Guard starts.
    #
    # - Setup Guard internals
    # - Evaluate the `Guardfile`
    # - Configure Notifiers
    # - Initialize the declared Guard plugins
    # - Start the available file change listener
    #
    # @option options [Boolean] clear if auto clear the UI should be done
    # @option options [Boolean] notify if system notifications should be shown
    # @option options [Boolean] debug if debug output should be shown
    # @option options [Array<String>] group the list of groups to start
    # @option options [String] watchdir the director to watch
    # @option options [String] guardfile the path to the Guardfile
    # @see CLI#start
    #
    def start(options = {})
      setup(options) unless running
      ::Guard::UI.debug 'Guard starts all plugins'
      runner.run(:start)
      listener.start
      ::Guard::UI.info "Guard is now watching at '#{ @watchdirs.join "', '" }'"

      _interactor_loop
    end

    # TODO: refactor (left to avoid breaking too many specs)
    def stop
      setup unless running

      #TODO: needed?
      @running = false

      listener.stop
      interactor.background
      ::Guard::UI.debug 'Guard stops all plugins'
      runner.run(:stop)
      ::Guard::Notifier.turn_off
      ::Guard::UI.info 'Bye bye...', reset: true
    end

    # Reload Guardfile and all Guard plugins currently enabled.
    # If no scope is given, then the Guardfile will be re-evaluated,
    # which results in a stop/start, which makes the reload obsolete.
    #
    # @param [Hash] scopes hash with a Guard plugin or a group scope
    #
    def reload(scopes = {})
      setup(options) unless running
      ::Guard::UI.clear(force: true)
      ::Guard::UI.action_with_scopes('Reload', scopes)

      if scopes.empty?
        evaluator.reevaluate_guardfile
      else
        runner.run(:reload, scopes)
      end
    end

    # Trigger `run_all` on all Guard plugins currently enabled.
    #
    # @param [Hash] scopes hash with a Guard plugin or a group scope
    #
    def run_all(scopes = {})
      setup unless running
      ::Guard::UI.clear(force: true)
      ::Guard::UI.action_with_scopes('Run', scopes)
      runner.run(:run_all, scopes)
    end

    # Pause Guard listening to file changes.
    #
    def pause(expected=nil)
      expected ||= :toggle
      raise ArgumentError, "invalid mode: #{expected.inspect}" unless [:toggle, :paused, :unpaused].include? expected

      current = listener.paused? ? :paused : :unpaused

      if expected == :toggle
        expected = current == :paused ? :unpaused : :paused
      end

      actions = { :unpaused => :unpause, :paused => :pause }
      if expected != current
        listener.send(actions[expected])
        ::Guard::UI.info "File modification listening is now #{expected.upcase}", reset: true
      end
    end

    # TODO: remove (left to avoid breaking too many specs)
    def _interactor_loop
      while interactor.foreground != :exit
        while pending_changes?
          _process_queue
        end
      end
      stop
    end

  end
end

# frozen_string_literal: true

require "optimist"

module Entitlements
  class Cli
    include ::Contracts::Core
    C = ::Contracts

    # This is the entrypoint to the CLI.
    #
    # argv - An Array with arguments, defaults to ARGV
    #
    # Returns an Integer with the exit status.
    # :nocov:
    Contract C::ArrayOf[C::Or[String, C::Bool, C::Num]] => Integer
    def self.run
      # Establish the logger object. Debugging is enabled or disabled based on options.
      logger = Logger.new(STDERR)
      logger.level = options[:debug] ? Logger::DEBUG : Logger::INFO
      Entitlements.set_logger(logger)

      # Set up configuration file.
      Entitlements.config_file = options[:"config-file"]
      Entitlements.validate_configuration_file!

      # Support predictive updates based on the environment, but allow the --full option to
      # suppress setting and using it.
      if ENV["ENTITLEMENTS_PREDICTIVE_STATE_DIR"] && !@options[:full]
        Entitlements::Data::Groups::Cached.load_caches(ENV["ENTITLEMENTS_PREDICTIVE_STATE_DIR"])
      end

      # Calculate differences.
      actions = Entitlements.calculate

      # No-op mode exits here.
      if @options[:noop]
        logger.info "No-op mode is set. Would make #{Entitlements.cache[:change_count]} change(s)."
        return 0
      end

      # No changes?
      if actions.empty?
        logger.info "No changes to be made. You're all set, friend! :sparkles:"
        return 0
      end

      # Execute the changes. This raises if it fails to apply a change or if auditors fail.
      Entitlements.execute(actions: actions)

      # Done.
      logger.info "Successfully applied #{Entitlements.cache[:change_count]} change(s)!"
      0
    end
    # :nocov:

    # Method access to options. `attr_reader` doesn't work here since it's a class variable.
    #
    # Takes no arguments.
    #
    # Returns a Hash.
    # :nocov:
    Contract C::None => C::HashOf[Symbol => C::Any]
    def self.options
      @options ||= begin
        o = initialize_options
        validate_options!(o)
        o
      end
    end
    # :nocov:

    # Parse the options given by ARGV and return a hash.
    #
    # Takes no arguments.
    #
    # Returns a Hash.
    # :nocov:
    Contract C::None => C::HashOf[Symbol => C::Any]
    def self.initialize_options
      Optimist.options do
        banner <<-EOS
        Configure authentication providers to look like the configuration declared in the files.

        Usage:

        $ deploy-entitlements --dir /path/to/configurations
        .
      EOS
        opt :"config-file",
            "Configuration file for application",
            type: :string,
            default: File.expand_path("../../config/entitlements/config.yaml", File.dirname(__FILE__))
        opt :noop,
            "no-op mode (do not actually apply configurations)",
            type: :boolean, default: false
        opt :full,
            "full deployment (skip predictive updates, if configured)",
            type: :boolean, default: false
        opt :debug,
            "debug messages enabled",
            type: :boolean, default: false
      end
    end
    # :nocov:

    # Validate command line options.
    #
    # options - Hash of options.
    #
    # Returns nothing.
    # :nocov:
    Contract C::HashOf[Symbol => C::Any] => nil
    def self.validate_options!(options)
      unless options[:"config-file"].is_a?(String) && File.file?(options[:"config-file"])
        raise ArgumentError, "Expected --config-file to be a valid file!"
      end
    end
    # :nocov:
  end
end

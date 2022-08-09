# frozen_string_literal: true

module Entitlements
  # Allows maintaining version compatibility with older versions of Ruby
  # :nocov:
  def self.ruby_version2?
    @ruby_version2 ||= (
        Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.0.0") &&
        Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.0.0")
    )
  end

  def self.ruby_version3?
    @ruby_version3 ||= (Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.0.0"))
  end
  # :nocov:
end

# Hey there! With our use of the "contracts" module, load order is important.

# Load third party dependencies first.
require "concurrent"

# Note that contracts.ruby has two specific ruby-version specific libraries, which we have vendored into lib/
# :nocov:
if Entitlements.ruby_version2?
  $LOAD_PATH.unshift(File.join(__dir__, File.expand_path("../contracts-ruby2/lib")))
else
  $LOAD_PATH.unshift(File.join(__dir__, File.expand_path("../contracts-ruby3/lib")))
end
# :nocov:

require "contracts"
require "erb"
require "logger"
require "ostruct"
require "set"
require "stringio"
require "uri"
require "yaml"

# Next, pre-declare any classes that are referenced from contracts.
module Entitlements
  class Auditor
    class Base; end
  end
  class Data
    class Groups
      class Cached; end
      class Calculated
        class Base; end
        class Ruby < Base; end
        class Text < Base; end
        class YAML < Base; end
      end
    end
    class People
      class Combined; end
      class Dummy; end
      class LDAP; end
      class YAML; end
    end
  end
  module Extras; end
  class Models
    class Action; end
    class Group; end
    class Person; end
    class RuleSet
      class Base; end
      class Ruby < Base; end
      class YAML < Base; end
    end
  end
  class Service
    class GitHub; end
    class LDAP; end
  end
end

module Entitlements
  include ::Contracts::Core
  C = ::Contracts

  IGNORED_FILES = Set.new(%w[README.md PR_TEMPLATE.md])

  # Allows interpretation of ERB for the configuration file to make things less hokey.
  class ERB < OpenStruct
    def self.render_from_hash(template, hash)
      new(hash).render(template)
    end

    def render(template)
      ::ERB.new(template, trim_mode: "-").result(binding)
    end
  end

  # Reset all Entitlements state
  #
  # Takes no arguments
  def self.reset!
    @cache = nil
    @child_classes = nil
    @config = nil
    @config_file = nil
    @config_path_override = nil
    @person_extra_methods = {}

    reset_extras!
    Entitlements::Data::Groups::Calculated.reset!
  end

  def self.reset_extras!
    extras_loaded = @extras_loaded
    if extras_loaded
      extras_loaded.each { |clazz| clazz.reset! if clazz.respond_to?(:reset!) }
    end
    @extras_loaded = nil
  end

  # Set up a dummy logger.
  #
  # Returns a Logger.
  Contract C::None => Logger
  def self.dummy_logger
    # :nocov:
    Logger.new(StringIO.new)
    # :nocov:
  end

  # Read the configuration file and return it as a hash.
  #
  # Takes no arguments.
  #
  # Returns a Hash.
  Contract C::None => C::HashOf[String => C::Any]
  def self.config
    @config ||= begin
      content = ERB.render_from_hash(File.read(config_file), {})
      ::YAML.safe_load(content)
    end
  end

  # Set the configuration directly to a Hash.
  #
  # config_hash - Desired value for the configuration.
  #
  # Returns the supplied configuration.
  Contract C::HashOf[String => C::Any] => C::HashOf[String => C::Any]
  def self.config=(config_hash)
    @config = config_hash
  end

  # Determine the configuration file location. Gets the default if
  # it is called before explicitly set.
  #
  # Returns a String.
  Contract C::None => String
  def self.config_file
    @config_file || File.expand_path("../config/entitlements/config.yaml", File.dirname(__FILE__))
  end

  # Allow an alternate configuration file to be set. When this is set, it
  # clears @config so it gets read upon the next invocation.
  #
  # path - Path to config file.
  Contract String => C::Any
  def self.config_file=(path)
    unless File.file?(path)
      raise "Specified config file = #{path.inspect} but it does not exist!"
    end

    @config_file = path
    @config = nil
  end

  # Get the configuration path for the groups. This is based on the relative
  # location to the configuration file if it doesn't start with a "/".
  #
  # Takes no arguments.
  #
  # Returns a String with the config path.
  def self.config_path
    return @config_path_override if @config_path_override
    base = config.fetch("configuration_path")
    return base if base.start_with?("/")
    File.expand_path(base, File.dirname(config_file))
  end

  # Set the configuration path for the groups. This will override the automatically
  # calculated config_path that respects the algorithm noted above.
  #
  # path - Path to the base directory of groups.
  #
  # Returns the config_path that was set.

  Contract String => C::Any
  def self.config_path=(path)
    unless path.start_with?("/")
      raise ArgumentError, "Path must be absolute when setting config_path!"
    end

    unless File.directory?(path)
      raise Errno::ENOENT, "config_path #{path.inspect} is not a directory!"
    end

    @config["configuration_path"] = path if @config
    @config_path_override = path
  end

  # Keep track of backends that are registered when backends are loaded.
  #
  # identifier - A String with the identifier for the backend as it appears in the configuration file
  # clazz      - A Class reference to the backend
  # priority   - An Integer with the order of execution (smaller = first)
  #
  # Returns nothing.
  Contract String, Class, Integer, C::Maybe[C::Bool] => C::Any
  def self.register_backend(identifier, clazz, priority)
    @backends ||= {}
    @backends[identifier] = { class: clazz, priority: priority }
  end

  # Return the registered backends.
  #
  # Takes no arguments.
  #
  # Returns a Hash of backend identifier => class and priority.
  Contract C::None => C::HashOf[String => C::HashOf[Symbol, C::Any]]
  def self.backends
    @backends || {}
  end

  # Load all extras configured by the "extras" key in the entitlements configuration.
  #
  # Takes no arguments.
  #
  # Returns nothing.
  Contract C::None => nil
  def self.load_extras
    Entitlements.config.fetch("extras", {}).each do |extra_name, extra_cfg|
      path = extra_cfg.key?("path") ? Entitlements::Util::Util.absolute_path(extra_cfg["path"]) : nil
      logger.debug "Loading extra #{extra_name} (path = #{path || 'default'})"
      Entitlements::Extras.load_extra(extra_name, path)
    end
    nil
  end

  # Handle a callback from Entitlements::Extras.load_extra to add a class to the tracker of loaded extra classes.
  #
  # clazz - Class that was loaded.
  #
  # Returns nothing.
  Contract Class => C::Any
  def self.record_loaded_extra(clazz)
    @extras_loaded ||= Set.new
    @extras_loaded.add(clazz)
  end

  # Register all filters configured by the "filters" key in the entitlements configuration.
  #
  # Takes no arguments.
  #
  # Returns nothing.
  Contract C::None => nil
  def self.register_filters
    Entitlements.config.fetch("filters", {}).each do |filter_name, filter_cfg|
      filter_class = filter_cfg.fetch("class")
      filter_clazz = Kernel.const_get(filter_class)
      filter_config = filter_cfg.fetch("config", {})

      logger.debug "Registering filter #{filter_name} (class: #{filter_class})"
      Entitlements::Data::Groups::Calculated.register_filter(filter_name, { class: filter_clazz, config: filter_config })
    end
    nil
  end

  @person_extra_methods = {}

  # Register a method on the Entitlements::Models::Person objects. Methods are registered at
  # a class level by extras. This updates @person_methods with a Hash of method_name => reference.
  #
  # method_name - A String with the extra method name to register.
  # method_ref  - A reference to the method within the appropriate class.
  #
  # Returns nothing.
  Contract String, C::Any => C::Any
  def self.register_person_extra_method(method_name, method_class_ref)
    @person_extra_methods[method_name.to_sym] = method_class_ref
  end

  # Get the current entries in @person_methods as a hash.
  #
  # Takes no arguments.
  #
  # Returns a Hash of method_name => reference.
  Contract C::None => C::HashOf[Symbol => C::Any]
  def self.person_extra_methods
    @person_extra_methods
  end

  # Return array of all registered child classes.
  #
  # Takes no arguments.
  #
  # Returns a Hash of instantiated Class objects, indexed by group name, sorted by priority.
  Contract C::None => C::HashOf[C::Or[Symbol, String] => Object]
  def self.child_classes
    @child_classes ||= begin
      backend_obj = Entitlements.config["groups"].map do |group_name, data|
        [group_name, Entitlements.backends[data["type"]][:class].new(group_name)]
      end.compact.to_h

      # Sort first by priority, then by whether this is a mirror or not (mirrors go last), and
      # finally by the length of the OU name from shortest to longest.
      backend_obj.sort_by do |k, v|
        [
          v.priority,
          Entitlements.config["groups"][k] && Entitlements.config["groups"][k].key?("mirror") ? 1 : 0,
          k.length
        ]
      end.to_h
    end
  end

  # Method to access the configured auditors.
  #
  # Takes no arguments.
  #
  # Returns an Array of Entitlements::Auditor::* objects.
  Contract C::None => C::ArrayOf[Entitlements::Auditor::Base]
  def self.auditors
    @auditors ||= begin
      if Entitlements.config.key?("auditors")
        Entitlements.config["auditors"].map do |auditor|
          unless auditor.is_a?(Hash)
            # :nocov:
            raise ArgumentError, "Configuration error: Expected auditor to be a hash, got #{auditor.inspect}!"
            # :nocov:
          end

          auditor_class = auditor.fetch("auditor_class")

          begin
            clazz = Kernel.const_get("Entitlements::Auditor::#{auditor_class}")
          rescue NameError
            raise ArgumentError, "Auditor class #{auditor_class.inspect} is invalid"
          end

          clazz.new(logger, auditor)
        end
      else
        []
      end
    end
  end

  # Global logger for this run of Entitlements.
  #
  # Takes no arguments.
  #
  # Returns a Logger.
  # :nocov:
  def self.logger
    @logger ||= dummy_logger
  end

  def self.set_logger(logger)
    @logger = logger
  end
  # :nocov:

  # Calculate - This runs the entitlements logic to calculate the differences, ultimately
  # populating a cache and returning a list of actions. The cache and actions can then be
  # consumed by `execute` to implement the changes.
  #
  # Takes no arguments.
  #
  # Returns the array of actions.
  Contract C::None => C::ArrayOf[Entitlements::Models::Action]
  def self.calculate
    # Load extras that are configured.
    Entitlements.load_extras if Entitlements.config.key?("extras")

    # Pre-fetch people from configured people data sources.
    Entitlements.prefetch_people

    # Register filters that are configured.
    Entitlements.register_filters if Entitlements.config.key?("filters")

    # Keep track of the total change count.
    cache[:change_count] = 0

    max_parallelism = Entitlements.config["max_parallelism"] || 1

    # Calculate old and new membership in each group.
    thread_pool = Concurrent::FixedThreadPool.new(max_parallelism)
    logger.debug("Begin prefetch and validate for all groups")
    prep_start = Time.now
    futures = Entitlements.child_classes.map do |group_name, obj|
      Concurrent::Future.execute({ executor: thread_pool }) do
        group_start = Time.now
        logger.debug("Begin prefetch and validate for #{group_name}")
        obj.prefetch
        obj.validate
        logger.debug("Finished prefetch and validate for #{group_name} in #{Time.now - group_start}")
      end
    end

    futures.each(&:value!)
    logger.debug("Finished all prefetch and validate in #{Time.now - prep_start}")

    logger.debug("Begin all calculations")
    calc_start = Time.now
    actions = []
    Entitlements.child_classes.map do |group_name, obj|
      obj.calculate
      if obj.change_count > 0
        logger.debug "Group #{group_name.inspect} contributes #{obj.change_count} change(s)."
        cache[:change_count] += obj.change_count
      end
      actions.concat(obj.actions)
    end
    logger.debug("Finished all calculations in #{Time.now - calc_start}")
    logger.debug("Finished all prefetch, validate, and calculation in #{Time.now - prep_start}")

    actions
  end

  # Method to execute all of the actions and run the auditors. Returns an Array of the exceptions
  # raised by auditors. Any exceptions raised by providers will be raised once the auditors are
  # executed.
  #
  # actions - An Array of Entitlements::Models::Action
  #
  # Returns nothing.
  Contract C::KeywordArgs[
    actions: C::ArrayOf[Entitlements::Models::Action]
  ] => nil
  def self.execute(actions:)
    # Set up auditors.
    Entitlements.auditors.each { |auditor| auditor.setup }

    # Track any raised exception to pass to the auditors.
    provider_exception = nil
    audit_exceptions = []
    successful_actions = Set.new

    # Sort the child classes by priority
    begin
      # Pre-apply changes for each class.
      Entitlements.child_classes.each do |_, obj|
        obj.preapply
      end

      # Apply changes from all actions.
      actions.each do |action|
        obj = Entitlements.child_classes.fetch(action.ou)
        obj.apply(action)
        successful_actions.add(action.dn)
      end
    rescue => e
      # Populate 'provider_exception' for the auditors and then raise the exception.
      provider_exception = e
      raise e
    ensure
      # Run the audit "commit" action for each auditor. This needs to happen despite any failures that
      # may occur when pre-applying or applying actions, because actions might have been applied despite
      # any failures raised. Run each audit, even if one fails, and batch up the exceptions for the end.
      # If there was an original exception from one of the providers, this block will be executed and then
      # that original exception will be raised.
      if Entitlements.auditors.any?
        logger.debug "Recording data to #{Entitlements.auditors.size} audit provider(s)"
        Entitlements.auditors.each do |audit|
          begin
            audit.commit(
              actions: actions,
              successful_actions: successful_actions,
              provider_exception: provider_exception
            )
            logger.debug "Audit #{audit.description} completed successfully"
          rescue => e
            logger.error "Audit #{audit.description} failed: #{e.class} #{e.message}"
            e.backtrace.each { |line| logger.error line }
            audit_exceptions << e
          end
        end
      end
    end

    # If we get here there were no provider exceptions. If there were audit exceptions raise them here.
    # If there were multiple exceptions we can only raise the first one, but log a message indicating this.
    return if audit_exceptions.empty?

    if audit_exceptions.size > 1
      logger.warn "There were #{audit_exceptions.size} audit exceptions. Only the first one is raised."
    end
    raise audit_exceptions.first
  end

  # Validate the configuration file.
  #
  # Takes no input.
  #
  # Returns nothing.
  Contract C::None => nil
  def self.validate_configuration_file!
    # Required attributes
    spec = {
      "configuration_path" => { required: true, type: String },
      "backends"           => { required: false, type: Hash },
      "people"             => { required: true, type: Hash },
      "people_data_source"  => { required: true, type: String },
      "groups"             => { required: true, type: Hash },
      "auditors"           => { required: false, type: Array },
      "filters"            => { required: false, type: Hash },
      "extras"             => { required: false, type: Hash },
      "max_parallelism"    => { required: false, type: Integer },
    }

    Entitlements::Util::Util.validate_attr!(spec, Entitlements.config, "Entitlements configuration file")

    # Make sure each group has a valid type, and then forward the validator to the child class.
    # If a named backend is chosen, merge the parameters from the backend with the parameters given
    # for the class configuration, and then remove all indication that a backend was used.
    Entitlements.config["groups"].each do |key, data|
      if data.key?("backend")
        unless Entitlements.config["backends"] && Entitlements.config["backends"].key?(data["backend"])
          raise "Entitlements configuration group #{key.inspect} references non-existing backend #{data['backend'].inspect}!"
        end

        backend = Entitlements.config["backends"].fetch(data["backend"])
        unless backend.key?("type")
          raise "Entitlements backend #{data['backend'].inspect} is missing a type!"
        end

        # Priority in the merge is given to the specific OU configured. Backend data is filled
        # in only as default values when not otherwise defined.
        Entitlements.config["groups"][key] = backend.merge(data)
        Entitlements.config["groups"][key].delete("backend")
        data = Entitlements.config["groups"][key]
      end

      unless data["type"].is_a?(String)
        raise "Entitlements configuration group #{key.inspect} does not properly declare a type!"
      end

      unless Entitlements.backends.key?(data["type"])
        raise "Entitlements configuration group #{key.inspect} has invalid type (#{data['type'].inspect})"
      end
    end

    # Good if nothing is raised by here.
    nil
  end

  # Method to go through each person data source and retrieve the list of people from it. Populates
  # Entitlements.cache[:people][<datasource>] with the objects that can be subsequently `read` from
  # with no penalty.
  #
  # Takes no arguments.
  #
  # Returns the Entitlements::Data::People::* object.
  Contract C::None => C::Any
  def self.prefetch_people
    Entitlements.cache[:people_obj] ||= begin
      people_data_sources = Entitlements.config.fetch("people", [])
      if people_data_sources.empty?
        raise ArgumentError, "At least one data source for people must be specified in the Entitlements configuration!"
      end

      # TODO: In the future, have separate data sources per group.
      people_data_source_name = Entitlements.config.fetch("people_data_source", "")
      if people_data_source_name.empty?
        raise ArgumentError, "The Entitlements configuration must define a people_data_source!"
      end
      unless people_data_sources.key?(people_data_source_name)
        raise ArgumentError, "The people_data_source #{people_data_source_name.inspect} is invalid!"
      end

      objects = people_data_sources.map do |ds_name, ds_config|
        people_obj = Entitlements::Data::People.new_from_config(ds_config)
        people_obj.read
        [ds_name, people_obj]
      end.to_h

      objects.fetch(people_data_source_name)
    end
  end

  # This is a global cache for the whole run of entitlements. To avoid passing objects around, since Entitlements
  # by its nature is a run-once-upon-demand application.
  #
  # Takes no arguments.
  #
  # Returns a Hash that contains the cache.
  #
  # Note: Since this is hit a lot, to avoid the performance penalty, Contracts is not used here.
  # :nocov:
  def self.cache
    @cache ||= {
      calculated: {},
      file_objects: {}
    }
  end
  # :nocov:
end

# Finally, load everything else. Order should be unimportant here.
require_relative "entitlements/auditor/base"
require_relative "entitlements/backend/base_controller"
require_relative "entitlements/backend/base_provider"
require_relative "entitlements/backend/dummy"
require_relative "entitlements/backend/ldap"
require_relative "entitlements/backend/member_of"
require_relative "entitlements/cli"
require_relative "entitlements/data/groups"
require_relative "entitlements/data/people"
require_relative "entitlements/extras"
require_relative "entitlements/extras/base"
require_relative "entitlements/models/action"
require_relative "entitlements/models/group"
require_relative "entitlements/models/person"
require_relative "entitlements/plugins"
require_relative "entitlements/plugins/dummy"
require_relative "entitlements/plugins/group_of_names"
require_relative "entitlements/plugins/posix_group"
require_relative "entitlements/rule/base"
require_relative "entitlements/service/ldap"
require_relative "entitlements/util/mirror"
require_relative "entitlements/util/override"
require_relative "entitlements/util/util"

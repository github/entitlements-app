# frozen_string_literal: true

# Loads extras either in this directory structure or elsewhere as specified by the end-user.

module Entitlements
  module Extras
    include ::Contracts::Core
    C = ::Contracts

    # Load and initialize extra functionality, whether in the `lib/extras` directory or in
    # some other place provided by the user.
    #
    # namespace - String with the namespace in Entitlements::Extras to be loaded
    # path      - Optionally, a String with the directory where the Entitlements::Extras::<Namespace>::Base class can be found
    #
    # Returns the Class object for the base of the extra.
    Contract String, C::Maybe[String] => Class
    def self.load_extra(namespace, path = nil)
      path ||= File.expand_path("./extras", __dir__)
      unless File.file?(File.join(path, namespace, "base.rb"))
        raise Errno::ENOENT, "Error loading #{namespace}: There is no file `base.rb` in directory `#{path}/#{namespace}`."
      end

      require File.join(path, namespace, "base.rb")
      class_name = ["Entitlements", "Extras", Entitlements::Util::Util.camelize(namespace), "Base"].join("::")
      clazz = Kernel.const_get(class_name)
      clazz.init

      # Register any rules defined by this class with the handler
      register_rules(clazz)

      # Register any additional methods on Entitlements::Models::Person
      register_person_extra_methods(clazz)

      # Record this extra's class as having been loaded.
      Entitlements.record_loaded_extra(clazz)

      # Contract return
      @namespace_class ||= {}
      @namespace_class[namespace] ||= clazz
    end

    # Register rules contained in this extra with a mapping of rules maintained by
    # Entitlements::Data::Groups::Calculated::Base.
    #
    # clazz - Initialized Entitlements::Extras::<Namespace>::Base object
    #
    # Returns nothing.
    Contract Class => nil
    def self.register_rules(clazz)
      return unless clazz.respond_to?(:rules)

      clazz.rules.each do |rule_name|
        rule_class_name = [clazz.to_s.sub(/::Base\z/, "::Rules"), Entitlements::Util::Util.camelize(rule_name)].join("::")
        rule_class = Kernel.const_get(rule_class_name)
        Entitlements::Data::Groups::Calculated.register_rule(rule_name, rule_class)
      end

      nil
    end

    # Register methods for Entitlements::Models::Person that are contained in this extra
    # with the Entitlements class.
    #
    # clazz - Initialized Entitlements::Extras::<Namespace>::Base object
    #
    # Returns nothing.
    Contract Class => nil
    def self.register_person_extra_methods(clazz)
      return unless clazz.respond_to?(:person_methods)

      clazz.person_methods.each do |method_name|
        clazz_without_base = clazz.to_s.split("::")[0..-2]
        method_class_name = [clazz_without_base, "PersonMethods"].join("::")
        method_class = Kernel.const_get(method_class_name)
        Entitlements.register_person_extra_method(method_name, method_class)
      end

      nil
    end
  end
end

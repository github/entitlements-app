# frozen_string_literal: true

require "yaml"

module Entitlements
  class Data
    class People
      class YAML
        include ::Contracts::Core
        C = ::Contracts

        # Parameters
        PARAMETERS = {
          "filename" => { required: true, type: String }
        }

        # Fingerprint for the object based on unique parameters from the group configuration. If the fingerprint
        # matches the same object should be re-used. This will raise an error if insufficient configuration is
        # given.
        #
        # config - Hash of configuration values as may be found in the Entitlements configuration file.
        #
        # Returns a String with the "fingerprint" for this configuration.
        Contract C::HashOf[String => C::Any] => String
        def self.fingerprint(config)
          PARAMETERS.keys.map { |key| config[key].inspect }.join("||")
        end

        # Construct this object based on parameters in a group configuration. This is the direct translation
        # between the Entitlements configuration file (which is always a Hash with configuration values) and
        # the object constructed from this class (which can have whatever structure makes sense).
        #
        # config - Hash of configuration values as may be found in the Entitlements configuration file.
        #
        # Returns Entitlements::Data::People::YAML object.
        # :nocov:
        Contract C::HashOf[String => C::Any] => Entitlements::Data::People::YAML
        def self.new_from_config(config)
          new(filename: config.fetch("filename"))
        end
        # :nocov:

        # Validate configuration options.
        #
        # key    - String with the name of the data source.
        # config - Hash with the configuration data.
        #
        # Returns nothing.
        # :nocov:
        Contract String, C::HashOf[String => C::Any] => nil
        def self.validate_config!(key, config)
          text = "YAML people configuration for data source #{key.inspect}"
          Entitlements::Util::Util.validate_attr!(PARAMETERS, config, text)
        end
        # :nocov:

        # Constructor.
        #
        # filename  - String with the filename to read.
        # people    - Optionally, Hash of { uid => Entitlements::Models::Person }
        Contract C::KeywordArgs[
          filename: String,
          people: C::Maybe[C::HashOf[String => Entitlements::Models::Person]]
        ] => C::Any
        def initialize(filename:, people: nil)
          @filename = filename
          @people = people
          @people_downcase = nil
        end

        # Read in the people from a file. Cache result for later access.
        #
        # uid - Optionally a uid to return. If not specified, returns the entire hash.
        #
        # Returns Hash of { uid => Entitlements::Models::Person } or one Entitlements::Models::Person.
        Contract C::Maybe[String] => C::Or[Entitlements::Models::Person, C::HashOf[String => Entitlements::Models::Person]]
        def read(uid = nil)
          @people ||= begin
            Entitlements.logger.debug "Loading people from #{filename.inspect}"
            raw_person_data = if Entitlements.ruby_version2?
              ::YAML.load(File.read(filename)).to_h
            else
              ::YAML.load(File.read(filename), permitted_classes: [Date]).to_h
            end

            raw_person_data.map do |id, data|
              [id, Entitlements::Models::Person.new(uid: id, attributes: data)]
            end.to_h
          end
          return @people if uid.nil?

          # Requested a specific user ID
          @people_downcase ||= @people.map { |person_uid, data| [person_uid.downcase, person_uid] }.to_h
          unless @people_downcase.key?(uid.downcase)
            raise Entitlements::Data::People::NoSuchPersonError, "read(#{uid.inspect}) matched no known person"
          end

          @people[@people_downcase[uid.downcase]]
        end

        private

        attr_reader :filename
      end
    end
  end
end

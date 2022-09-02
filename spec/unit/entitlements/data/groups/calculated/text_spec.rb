# frozen_string_literal: true

require_relative "../../../../spec_helper"

describe Entitlements::Data::Groups::Calculated::Text do
  before(:each) do
    Entitlements::Extras.load_extra("ldap_group")
    Entitlements::Extras.load_extra("orgchart")
    setup_default_filters
  end

  let(:people_obj) { Entitlements::Data::People::YAML.new(filename: fixture("people.yaml")) }
  let(:cache) { { people_obj: people_obj } }
  let(:filename) { fixture("ldap-config/text/example.txt") }
  let(:subject) { described_class.new(filename: filename) }

  describe "#members" do
    it "returns the expected member list" do
      result = subject.members
      result_set = Set.new(result.map { |i| i.uid })
      answer_array = %w[blackmanx russianblue RAGAMUFFIn mainecoon]
      answer_set = Set.new(answer_array)
      expect(result_set).to eq(answer_set)
    end

    it "handles case-insensitivity properly" do
      filename = fixture("ldap-config/text/example2.txt")
      subject = described_class.new(filename: filename)
      result = subject.members
      result_set = Set.new(result.map { |i| i.uid })
      answer_array = %w[oJosazuLEs NEBELUNg khaomanee cyprus cheetoh chausie]
      answer_set = Set.new(answer_array)
      expect(result_set).to eq(answer_set)
    end
  end

  describe "#description" do
    it "returns the string when one is set" do
      filename = fixture("ldap-config/text/example.txt")
      subject = described_class.new(filename: filename)
      expect(subject.description).to eq("Example")
    end

    it "returns an empty-string when description is undefined" do
      filename = fixture("ldap-config/text/no-description.txt")
      subject = described_class.new(filename: filename)
      expect(subject.description).to eq("")
    end

    it "raises an error when there is a duplicate description" do
      filename = fixture("ldap-config/text/duplicate-description.txt")
      subject = described_class.new(filename: filename)
      expect { subject.description }.to raise_error(RuntimeError, /description key is duplicated in .+duplicate-description.txt!/)
    end

    it "raises an error when the description is specified with !=" do
      filename = fixture("ldap-config/text/not-equals-description.txt")
      subject = described_class.new(filename: filename)
      expect do
        subject.description
      end.to raise_error(RuntimeError, /description cannot use '!=' operator in .+not-equals-description.txt!/)
    end
  end

  describe "#initialize_filters" do
    it "returns defaults when no filters are specified" do
      filename = fixture("ldap-config/filters/no-filters.txt")
      subject = described_class.new(filename: filename)
      answer = default_filters
      expect(subject.filters).to eq(answer)
    end

    it "sets contractors filter to none when specified in file" do
      filename = fixture("ldap-config/filters/one-filter-true.txt")
      subject = described_class.new(filename: filename)
      answer = default_filters
      expect(subject.filters).to eq(answer.merge("contractors" => :none))
    end

    it "sets contractors filter to all when specified in file" do
      filename = fixture("ldap-config/filters/one-filter-false.txt")
      subject = described_class.new(filename: filename)
      answer = default_filters
      expect(subject.filters).to eq(answer.merge("contractors" => :all))
    end

    it "sets contractors filter to an array when specified in file" do
      filename = fixture("ldap-config/filters/multiple-contractors-1.txt")
      subject = described_class.new(filename: filename)
      answer = default_filters
      # case insensitivity comes later
      expect(subject.filters).to eq(answer.merge("contractors" => %w[pixiEBOB SErengeti]))
    end

    it "raises an error when key == 'filter_'" do
      filename = fixture("ldap-config/filters/bad-data-structure.txt")
      expect do
        described_class.new(filename: filename)
      end.to raise_error(/In .+\/bad-data-structure.txt, cannot have a key named "filter_"!/)
    end

    it "returns an array with a single entry for a non-keyword" do
      filename = fixture("ldap-config/filters/one-filter-value.txt")
      subject = described_class.new(filename: filename)
      answer = default_filters
      expect(subject.filters).to eq(answer.merge("contractors" => %w[kittens]))
    end

    it "raises an error when the key of a filter is not expected" do
      filename = fixture("ldap-config/filters/one-filter-invalid-key.txt")
      expect do
        described_class.new(filename: filename)
      end.to raise_error(/In .+\/one-filter-invalid-key.txt, the key filter_fluffy_kittens is invalid!/)
    end

    it "raises an error when the key of a filter is repeated" do
      filename = fixture("ldap-config/filters/one-filter-repeated.txt")
      expect do
        described_class.new(filename: filename)
      end.to raise_error(/In .+\/one-filter-repeated.txt, filter_contractors cannot contain multiple entries when 'all' or 'none' is used!/)
    end

    it "raises an error when != is used in a filter" do
      filename = fixture("ldap-config/filters/filter-not-equal.txt")
      expect do
        described_class.new(filename: filename)
      end.to raise_error(/The filter contractors cannot use '!=' operator in .+filter-not-equal.txt!/)
    end

    it "treats an expired contractor filter as not even being present" do
      filename = fixture("ldap-config/filters/expiration-contractor-expired.txt")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters)
    end

    it "treats a non-expired contractor filter normally" do
      filename = fixture("ldap-config/filters/expiration-contractor-nonexpired.txt")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters.merge("contractors" => %w[pixiebob]))
    end

    it "removes expired contractor filters and keeps non-expired ones" do
      filename = fixture("ldap-config/filters/expiration-contractor-mixedexpired.txt")
      subject = described_class.new(filename: filename)
      expect(subject.filters).to eq(default_filters.merge("contractors" => %w[pixiebob]))
    end
  end

  describe "#initialize_metadata" do
    it "returns an empty hash if there is no metadata method" do
      filename = fixture("ldap-config/metadata/undefined.txt")
      subject = described_class.new(filename: filename)
      expect(subject.metadata).to eq({})
    end

    it "raises an error if metadata contains a nil key" do
      filename = fixture("ldap-config/metadata/bad-data-key.txt")
      message = "In #{filename}, cannot have a key named \"metadata_\"!"
      expect do
        described_class.new(filename: filename)
      end.to raise_error(message)
    end

    it "raises an error if metadata contains a repeated key" do
      filename = fixture("ldap-config/metadata/repeated-data-key.txt")
      message = "In #{filename}, the key metadata_kittens is repeated!"
      expect do
        described_class.new(filename: filename)
      end.to raise_error(message)
    end

    it "raises an error if != operator is used" do
      filename = fixture("ldap-config/metadata/not-equal-metadata.txt")
      message = "The key metadata_kittens cannot use '!=' operator in #{filename}!"
      expect do
        described_class.new(filename: filename)
      end.to raise_error(message)
    end

    it "returns the hash of metadata" do
      filename = fixture("ldap-config/metadata/good.txt")
      subject = described_class.new(filename: filename)
      expect(subject.metadata).to eq("kittens" => "awesome", "puppies" => "young dogs")
    end

    it "raises an error if expiration is given to metadata" do
      filename = fixture("ldap-config/metadata/expiration.txt")
      message = "In #{filename}, the key metadata_kittens cannot have additional setting(s) \"expiration\"!"
      expect { described_class.new(filename: filename) }.to raise_error(message)
    end
  end

  describe "#modifiers" do
    it "returns an empty hash if there is no modifiers method" do
      filename = fixture("ldap-config/metadata/undefined.txt")
      subject = described_class.new(filename: filename)
      expect(subject.modifiers).to eq({})
    end

    it "returns a hash of the modifier methods" do
      filename = fixture("ldap-config/expiration/valid-text.txt")
      subject = described_class.new(filename: filename)
      expect(subject.modifiers).to eq("expiration"=>"2043-01-01")
    end
  end

  describe "#rules" do
    let(:filename) { fixture("ldap-config/text/multiple.txt") }

    it "returns OR of the conditions without reserved keys" do
      answer = {
        "or"=>[
          {"management"=>"MAINECOON"},
          {"group"=>"cn=chickens,ou=Poultry,dc=kittens,dc=net"},
          {"username"=>"BlackManx"}
        ]
      }
      result = subject.send(:rules)
      expect(result).to eq(answer)
    end

    context "with no conditions" do
      let(:filename) { fixture("ldap-config/text/empty.txt") }

      it "raises an error" do
        expect { subject.send(:rules) }.to raise_error(RuntimeError, /No conditions were found in .+empty\.txt!/)
      end
    end

    context "with no conditions, but metadata_no_conditions_ok set" do
      let(:filename) { fixture("ldap-config/text/empty-but-ok.txt") }

      it "returns an empty hash" do
        expect(subject.send(:rules)).to eq({"always" => false})
      end
    end

    context "including an unknown method" do
      let(:filename) { fixture("ldap-config/text/unknown.txt") }

      it "raises an error" do
        expect { subject.send(:rules) }.to raise_error(RuntimeError, /The method "foobar" is not allowed in .+unknown\.txt!/)
      end
    end

    context "including a non-whitelisted method" do
      let(:filename) { fixture("ldap-config/text/disallowed.txt") }

      it "raises an error" do
        expect { subject.send(:rules) }.to raise_error(RuntimeError, /The method "fizzbuzz" is not allowed in .+disallowed\.txt!/)
      end
    end

    context "including an alias for a whitelisted method" do
      let(:filename) { fixture("ldap-config/text/alias_method.txt") }

      it "returns the expected rule set" do
        answer = {"or"=>[{"group"=>"pizza_teams/from_username"}]}
        result = subject.send(:rules)
        expect(result).to eq(answer)
      end
    end

    context "including an alias for a non-whitelisted method" do
      let(:filename) { fixture("ldap-config/text/disallowed_alias.txt") }

      it "raises an error referencing the alias" do
        expect(subject).to receive(:function_for).with("fizzbuzz_alias").and_return("fizzbuzz")
        expect(subject).to receive(:function_for).with("management").and_return("management")
        expect do
          subject.send(:rules)
        end.to raise_error(RuntimeError, /The method "fizzbuzz_alias" is not allowed in .+disallowed_alias\.txt!/)
      end
    end

    context "when a key is duplicated" do
      let(:filename) { fixture("ldap-config/text/duplicated.txt") }

      it "puts all of the values into the OR array" do
        answer = {
          "or"=>[
            {"management"=>"MAINECOON"},
            {"management"=>"balinese"},
            {"username"=>"nebelung"},
            {"username"=>"cheetoh"},
            {"username"=>"cyprus"}
          ]
        }
        result = subject.send(:rules)
        expect(result).to eq(answer)
      end
    end

    context "with a single != operator" do
      let(:filename) { fixture("ldap-config/text/one-not-equal.txt") }

      it "constructs and/not tree" do
        answer = {
          "and" => [
            {"or"=>[
              {"management"=>"MAINECOON"},
              {"group"=>"cn=chickens,ou=Poultry,dc=kittens,dc=net"},
              {"username"=>"BlackManx"}
            ]},
            {"and"=>[
              {"not"=>{"username"=>"russianblue"}}
            ]}
          ]
        }
        result = subject.send(:rules)
        expect(result).to eq(answer)
      end
    end

    context "with multiple != operators" do
      let(:filename) { fixture("ldap-config/text/multiple-not-equal.txt") }

      it "constructs and/not tree" do
        answer = {
          "and" => [
            {"or"=>[
              {"management"=>"MAINECOON"},
              {"group"=>"cn=chickens,ou=Poultry,dc=kittens,dc=net"}
            ]},
            {"and"=>[
              {"not"=>{"username"=>"BlackManx"}},
              {"not"=>{"username"=>"russianblue"}}
            ]}
          ]
        }
        result = subject.send(:rules)
        expect(result).to eq(answer)
      end
    end

    context "with only a != operator" do
      let(:filename) { fixture("ldap-config/text/only-not-equal.txt") }

      it "raises an error" do
        expect do
          subject.send(:rules)
        end.to raise_error(RuntimeError, /No conditions were found in .+only-not-equal.txt!/)
      end
    end

    context "with negative group" do
      let(:filename) { fixture("ldap-config/text/positive-negative-ldap-group.txt") }

      it "does not exclude contractors" do
        answer = {
          "and" => [
            {"or"=>[
              {"management"=>"MAINECOON"}
            ]},
            {"and"=>[
              {"not"=>{"group"=>"no_contractors"}}
            ]}
          ]
        }
        result = subject.send(:rules)
        expect(result).to eq(answer)
      end
    end

    context "with a &= custom filter specified" do
      let(:filename) { fixture("ldap-config/text/custom-filter.txt") }

      it "applies 'and' logic with the stated condition" do
        answer = {
          "and" => [
            { "group" => "pizza_teams/grumpy-cat-eng" },
            { "or" => [
              { "username" => "BlackManx" },
              { "username" => "ragamuffin" },
              { "username" => "peterbald" },
              { "username" => "mainecoon" }
            ]}
          ]
        }
        result = subject.send(:rules)
        expect(result).to eq(answer)
      end
    end

    context "with multiple &= custom filters specified" do
      let(:filename) { fixture("ldap-config/text/custom-filter-multiple.txt") }

      it "applies 'and' logic with the stated conditions" do
        answer = {
          "and" => [
            { "or" => [
              { "group" => "pizza_teams/grumpy-cat-eng" },
              { "direct_report" => "ojosazules" },
            ]},
            { "or" => [
              { "username" => "BlackManx" },
              { "username" => "ragamuffin" },
              { "username" => "peterbald" },
              { "username" => "mainecoon" },
              { "username" => "nebelung" },
              { "username" => "ojosazules" }
            ]}
          ]
        }
        result = subject.send(:rules)
        expect(result).to eq(answer)
      end
    end

    context "with expiration" do
      context "not expired" do
        let(:filename) { fixture("ldap-config/text/expiration-not-expired.txt") }

        it "constructs the correct rule set" do
          answer = {
            "or" => [
              { "username" => "blackmanx" },
              { "username" => "russianblue" },
              { "username" => "mainecoon" }
            ]
          }
          result = subject.send(:rules)
          expect(result).to eq(answer)
        end
      end

      context "already expired" do
        let(:filename) { fixture("ldap-config/text/expiration-already-expired.txt") }

        it "constructs the correct rule set" do
          answer = {
            "or" => [
              { "username" => "mainecoon" }
            ]
          }
          result = subject.send(:rules)
          expect(result).to eq(answer)
        end
      end

      context "already expired but expirations are disabled" do
        let(:filename) { fixture("ldap-config/text/expiration-already-expired.txt") }

        it "constructs the correct rule set" do
          Entitlements.config["ignore_expirations"] = true
          answer = {
            "or" => [
              { "username" => "blackmanx" },
              { "username" => "russianblue" },
              { "username" => "mainecoon" }
            ]
          }
          result = subject.send(:rules)
          expect(result).to eq(answer)
        end
      end

      context "mix of not expired and already expired" do
        let(:filename) { fixture("ldap-config/text/expiration-mixed-expired.txt") }

        it "constructs the correct rule set" do
          answer = {
            "or" => [
              { "username" => "blackmanx" },
              { "username" => "mainecoon" }
            ]
          }
          result = subject.send(:rules)
          expect(result).to eq(answer)
        end
      end

      context "expiration date unparseable" do
        let(:filename) { fixture("ldap-config/text/expiration-date-unparseable.txt") }

        it "raises an error" do
          expect do
            subject.send(:rules)
          end.to raise_error(ArgumentError, /Invalid expiration date "FluffyKittens12345" in .+expiration-date-unparseable.txt/)
        end
      end

      context "expiration predicate unparseable" do
        let(:filename) { fixture("ldap-config/text/expiration-predicate-unparseable.txt") }

        it "raises an error" do
          expect do
            subject.send(:rules)
          end.to raise_error(ArgumentError, /Unparseable semicolon predicate "expiration = Fluffy Kittens 12345" in .+expiration-predicate-unparseable.txt!/)
        end
      end
    end
  end

  describe "#parsed_data" do
    it "returns a hash of parsed key-value pairs" do
      result = subject.send(:parsed_data)
      expect(result).to eq(
        "description" =>{"=" => [{ key: "Example" }], "!=" => [], "&=" => []},
        "management" => {"=" => [{ key: "MAINECOON" }], "!=" => [], "&=" => []}
      )
    end

    context "with shorthand filter lines" do
      let(:filename) { fixture("ldap-config/text/shorthand.txt") }

      it "adjusts keys to support filter data structure" do
        result = subject.send(:parsed_data)
        answer = {
          "description" => {"=" => [{ key: "A place for contractors and employees to hang out" }], "!=" => [], "&=" => []},
          "filter_contractors" => {"=" => [{ key: "none" }], "!=" => [], "&=" => []},
          "filter_pre-hires" => {"=" => [{ key: "all" }], "!=" => [], "&=" => []},
          "username" => {"=" => [{ key: "pixiebob" }, { key: "russianblue" }], "!=" => [], "&=" => []}
        }
        expect(result).to eq(answer)
      end
    end

    context "with shorthand filter lines causing duplication" do
      let(:filename) { fixture("ldap-config/text/shorthand-duplicated.txt") }

      it "raises due to the duplication" do
        expect do
          described_class.new(filename: filename)
        end.to raise_error(%r{In .+/text/shorthand-duplicated.txt, filter_contractors cannot contain multiple entries when 'all' or 'none' is used!})
      end
    end

    context "when a line is unparseable" do
      let(:filename) { fixture("ldap-config/text/invalid.txt") }

      it "raises an error" do
        expect do
          subject.send(:parsed_data)
        end.to raise_error(RuntimeError, /Unparseable line "description: Example" in .+invalid.txt!/)
      end
    end

    context "with the 'contractor' method used" do
      let(:filename) { fixture("ldap-config/text/contractor.txt") }

      it "raises an error" do
        expect do
          subject.send(:parsed_data)
        end.to raise_error(RuntimeError, /Rule Error: contractor is not a valid function .+contractor.txt!/)
      end
    end

    context "with the predicate containing expiration semicolons" do
      let(:filename) { fixture("ldap-config/text/expiration-not-expired.txt") }

      it "parses correctly" do
        result = subject.send(:parsed_data)
        answer = {
          "description" => {"=" => [{ key: "Expiration rule testing" }], "!=" => [], "&=" => []},
          "username" => {
            "=" => [
              { key: "blackmanx", expiration: "2018-05-01" },
              { key: "russianblue", expiration: "2018-05-01" },
              { key: "mainecoon" }
            ],
            "!=" => [],
            "&=" => []
          }
        }
        expect(result).to eq(answer)
      end
    end

    context "with the predicate containing invalid semicolons" do
      let(:filename) { fixture("ldap-config/text/invalid-semicolons.txt") }

      it "raises an error" do
        expect do
          subject.send(:parsed_data)
        end.to raise_error(ArgumentError, /Rule Error: Invalid semicolon predicate "expires" in .+invalid-semicolons.txt!/)
      end
    end

    context "with the description containing semicolons" do
      let(:filename) { fixture("ldap-config/text/semicolons-in-description.txt") }

      it "parses correctly" do
        result = subject.send(:parsed_data)
        answer = {
          "description" => {"=" => [{ key: "the; description; can; have; semicolons" }], "!=" => [], "&=" => []},
          "username" => {"=" => [{ key: "mainecoon" }], "!=" => [], "&=" => []}
        }
        expect(result).to eq(answer)
      end
    end
  end
end

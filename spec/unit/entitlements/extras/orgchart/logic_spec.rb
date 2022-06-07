# frozen_string_literal: true

require_relative "../../../spec_helper"
require_relative "../../../../../lib/entitlements/models/person"

require "yaml"

describe Entitlements::Extras::Orgchart::Logic do
  before(:each) do
    Entitlements::Extras.load_extra("orgchart")
  end

  let(:ceo)   { Entitlements::Models::Person.new(uid: "the-ceo") }
  let(:cto)   { Entitlements::Models::Person.new(uid: "the-cto") }
  let(:vp1)   { Entitlements::Models::Person.new(uid: "VP1") }
  let(:vp2)   { Entitlements::Models::Person.new(uid: "vp2") }
  let(:dir1a) { Entitlements::Models::Person.new(uid: "dir1a") }
  let(:dir1b) { Entitlements::Models::Person.new(uid: "dir1b") }
  let(:dir2a) { Entitlements::Models::Person.new(uid: "dir2a") }
  let(:dir2b) { Entitlements::Models::Person.new(uid: "dir2b") }
  let(:pe1a)  { Entitlements::Models::Person.new(uid: "pe1a") }
  let(:mgr1a) { Entitlements::Models::Person.new(uid: "mgr1a") }
  let(:mgr2a) { Entitlements::Models::Person.new(uid: "mgr2a") }
  let(:ic1a)  { Entitlements::Models::Person.new(uid: "IC1a") }
  let(:ic1b)  { Entitlements::Models::Person.new(uid: "ic1b") }
  let(:ic2a)  { Entitlements::Models::Person.new(uid: "ic2a") }

  let(:people) { [ceo, cto, vp1, vp2, dir1a, dir1b, dir2a, dir2b, pe1a, mgr1a, mgr2a, ic1a, ic1b, ic2a] }
  let(:people_hash) { people.map { |entry| [entry.uid, entry] }.to_h }
  let(:subject) { described_class.new(people: people_hash) }
  let(:manager_map_data) do
    {
      ceo.uid.downcase => { "status" => "employee", "manager" => ceo.uid.downcase },
      cto.uid.downcase => { "status" => "employee", "manager" => ceo.uid.downcase },
      vp1.uid.downcase => { "status" => "employee", "manager" => cto.uid.downcase },
      vp2.uid.downcase => { "status" => "employee", "manager" => cto.uid.downcase },
      dir1a.uid.downcase => { "status" => "employee", "manager" => vp1.uid.downcase },
      dir1b.uid.downcase => { "status" => "employee", "manager" => vp1.uid.downcase },
      dir2a.uid.downcase => { "status" => "employee", "manager" => vp2.uid.downcase },
      dir2b.uid.downcase => { "status" => "employee", "manager" => vp2.uid.downcase },
      pe1a.uid.downcase => { "status" => "employee", "manager" => dir1a.uid.downcase },
      mgr1a.uid.downcase => { "status" => "employee", "manager" => dir1a.uid.downcase },
      mgr2a.uid.downcase => { "status" => "employee", "manager" => dir2a.uid.downcase },
      ic1a.uid.downcase => { "status" => "employee", "manager" => mgr1a.uid.downcase },
      ic1b.uid.downcase => { "status" => "employee", "manager" => mgr1a.uid.downcase },
      ic2a.uid.downcase => { "status" => "employee", "manager" => mgr2a.uid.downcase }
    }
  end

  before(:each) do
    allow(Entitlements).to receive(:manager_map_data).and_return(manager_map_data)
    allow(Entitlements::Util::Util).to receive(:absolute_path).with("manager-map-stub.yaml").and_return("manager-map-stub.yaml")
    allow(File).to receive(:file?).with("manager-map-stub.yaml").and_return(true)
    allow(File).to receive(:read).with("manager-map-stub.yaml").and_return(YAML.dump(manager_map_data))
  end

  let(:entitlements_config_hash) do
    {
      "extras" => {
        "orgchart" => {
          "manager_map_file" => "manager-map-stub.yaml"
        }
      }
    }
  end

  describe "#direct_reports" do
    it "returns direct report objects for managers" do
      expect(subject.direct_reports(dir1a)).to eq(Set.new([pe1a, mgr1a]))
      expect(subject.direct_reports(dir2a)).to eq(Set.new([mgr2a]))
      expect(subject.direct_reports(mgr1a)).to eq(Set.new([ic1a, ic1b]))
      expect(subject.direct_reports(ceo)).to eq(Set.new([cto]))
    end

    it "returns empty-set for people with no direct reports" do
      expect(subject.direct_reports(ic1a)).to eq(Set.new)
      expect(subject.direct_reports(pe1a)).to eq(Set.new)
    end
  end

  describe "#all_reports" do
    it "returns direct and indirect report objects for managers" do
      expect(subject.all_reports(dir1a)).to eq(Set.new([pe1a, mgr1a, ic1a, ic1b]))
      expect(subject.all_reports(dir2a)).to eq(Set.new([mgr2a, ic2a]))
      expect(subject.all_reports(mgr1a)).to eq(Set.new([ic1a, ic1b]))
      expect(subject.all_reports(vp1)).to eq(Set.new([dir1a, dir1b, pe1a, mgr1a, ic1a, ic1b]))
    end

    it "returns empty-set for people with no reports" do
      expect(subject.all_reports(ic1a)).to eq(Set.new)
      expect(subject.all_reports(pe1a)).to eq(Set.new)
    end
  end

  describe "#management_chain" do
    it "returns empty set for a person who reports to themself" do
      expect(subject.management_chain(ceo)).to eq(Set.new)
    end

    it "returns a proper chain for a person with reports" do
      expect(subject.management_chain(dir1a)).to eq(Set.new([vp1, cto, ceo]))
    end

    it "returns a proper chain for a person with no reports" do
      expect(subject.management_chain(ic1a)).to eq(Set.new([mgr1a, dir1a, vp1, cto, ceo]))
    end
  end
end

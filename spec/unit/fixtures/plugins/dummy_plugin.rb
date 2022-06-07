class Entitlements::Plugins::DummyPlugin < Entitlements::Plugins
  def self.override_hash(_group, _plugin, _ldap)
    { "foo" => "bar" }
  end
end

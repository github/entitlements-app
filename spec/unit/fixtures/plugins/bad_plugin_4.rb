class Entitlements::Plugins::BadPlugin4 < Entitlements::Plugins
  def self.override_hash(*args)
    :kittens
  end
end

# frozen_string_literal: true

require "decidim/suomifi/test/runtime"

# Configure the Suomi.fi module. This call is required to set the
# @configured flag to true, which the engine checks during boot
# to decide whether to register the Devise OmniAuth strategy
# and verification workflow.
Decidim::Suomifi.configure do |config|
  config.mode = :test
  config.scope_of_data = :medium_extensive
end

# Register Suomi.fi as a Decidim OmniAuth provider. In Decidim v0.31+,
# providers are no longer read from config/secrets.yml. They must be
# registered explicitly here instead.
Decidim.configure do |config|
  config.omniauth_providers[:suomifi] = {
    enabled: true,
    mode: "test",
    icon: "globe-line"
  }
end

Decidim::Suomifi::Test::Runtime.initialize

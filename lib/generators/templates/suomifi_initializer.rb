# frozen_string_literal: true

cert_path = Rails.application.root.join("config", "cert")

Decidim::Suomifi.configure do |config|
  config.scope_of_data = :medium_extensive
  # Define the service provider entity ID included in the Suomi.fi metadata:
  # config.sp_entity_id = "https://www.example.org/users/auth/suomifi/metadata"
  # Or define it in your application configuration and apply it here:
  # config.sp_entity_id = Rails.application.config.suomifi_entity_id
  config.certificate_file = "#{cert_path}/suomifi.crt"
  config.private_key_file = "#{cert_path}/suomifi.key"
  # Enable automatically assigned emails
  config.auto_email_domain = "example.org"
end

# Register Suomi.fi as a Decidim OmniAuth provider. In Decidim v0.31+,
# providers are no longer read from config/secrets.yml. They must be
# registered explicitly here instead.
Decidim.configure do |config|
  config.omniauth_providers[:suomifi] = {
    enabled: Decidim::Env.new("OMNIAUTH_SUOMIFI_ENABLED", false),
    mode: Decidim::Env.new("OMNIAUTH_SUOMIFI_MODE", nil),
    icon: "globe-line"
  }
end

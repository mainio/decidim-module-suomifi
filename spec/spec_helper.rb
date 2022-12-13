# frozen_string_literal: true

require "decidim/dev"
require "omniauth-suomifi/test"
require "webmock"

require "decidim/suomifi/test/cert_store"
require "decidim/suomifi/test/runtime"

require "simplecov" if ENV["SIMPLECOV"] || ENV["CODECOV"]
if ENV["CODECOV"]
  require "codecov"
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
end

ENV["ENGINE_ROOT"] = File.dirname(__dir__)

Decidim::Dev.dummy_app_path =
  File.expand_path(File.join(__dir__, "decidim_dummy_app"))

require_relative "base_spec_helper"

Decidim::Suomifi::Test::Runtime.initializer do
  # Silence the OmniAuth logger
  OmniAuth.config.logger = Logger.new("/dev/null")

  # Configure the Suomi.fi module
  Decidim::Suomifi.configure do |config|
    cs = Decidim::Suomifi::Test::Runtime.cert_store

    config.mode = :test
    config.scope_of_data = :medium_extensive
    config.sp_entity_id = "http://1.lvh.me/users/auth/suomifi/metadata"
    config.certificate = cs.certificate.to_pem
    config.private_key = cs.private_key.to_pem
    config.action_authorizer = "Decidim::Suomifi::ActionAuthorizer"
    config.use_suomifi_email = true
    config.auto_email_domain = "1.lvh.me"
    config.extra = {
      assertion_consumer_service_url: "http://1.lvh.me/users/auth/suomifi/callback",
      idp_cert_multi: {
        signing: [cs.sign_certificate.to_pem]
      }
    }
  end
end

Decidim::Suomifi::Test::Runtime.load_app

# Add the test templates path to ActionMailer
ActionMailer::Base.prepend_view_path(
  File.expand_path(File.join(__dir__, "fixtures", "mailer_templates"))
)

RSpec.configure do |config|
  # Make it possible to sign in and sign out the user in the request type specs.
  # This is needed because we need the request type spec for the omniauth
  # callback tests.
  config.include Devise::Test::IntegrationHelpers, type: :request

  config.before do
    # Respond to the metadata request with a stubbed request to avoid external
    # HTTP calls.
    base_path = File.expand_path(File.join(__dir__, ".."))
    metadata_path = File.expand_path(
      File.join(base_path, "spec", "fixtures", "files", "idp_metadata.xml")
    )
    stub_request(
      :get,
      "https://testi.apro.tunnistus.fi/static/metadata/idp-metadata.xml"
    ).to_return(status: 200, body: File.new(metadata_path), headers: {})
  end

  config.before do
    # Re-define the password validators due to a bug in the "email included"
    # check which does not work well for domains such as "1.lvh.me" that we are
    # using during tests.
    PasswordValidator.send(:remove_const, :VALIDATION_METHODS)
    PasswordValidator.const_set(
      :VALIDATION_METHODS,
      [
        :password_too_short?,
        :password_too_long?,
        :not_enough_unique_characters?,
        :name_included_in_password?,
        :nickname_included_in_password?,
        # :email_included_in_password?,
        :domain_included_in_password?,
        :password_too_common?,
        :blacklisted?
      ].freeze
    )
  end
end

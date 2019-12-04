# frozen_string_literal: true

require "omniauth"
require "omniauth-suomifi"
require "henkilotunnus"

require_relative "suomifi/version"
require_relative "suomifi/engine"
require_relative "suomifi/authentication"
require_relative "suomifi/verification"
require_relative "suomifi/mail_interceptors"

module Decidim
  module Suomifi
    include ActiveSupport::Configurable

    @configured = false

    # :production - For Suomi.fi production environment
    # :test - For Suomi.fi test environment
    config_accessor :mode, instance_reader: false

    # :limited - Limited scope
    # :medium_extensive - Medium-extensive scope
    # :extensive - Extensive scope
    config_accessor :scope_of_data do
      :medium_extensive
    end

    # Defines the email domain for the auto-generated email addresses for the
    # user accounts. You can also use the person's own email address possibly
    # stored in the Suomi.fi database with the option `use_suomifi_email`. Not
    # all people have email address stored in Suomi.fi and some people may have
    # incorrect email address stored there.
    #
    # In case this is defined, the user will be automatically assigned an email
    # such as "suomifi-identifier@auto-email-domain.fi" upon their registration.
    #
    # In case this is not defined, the default is the organization's domain.
    config_accessor :auto_email_domain

    # Defines whether to use the person's email address stored in the Suomi.fi
    # database for the user account. Some people do not actively update these
    # email addresses and some people may have a wrong email address stored in
    # the Suomi.fi database which can belong to another person in the worst case
    # scenario which can cause confusion among the participants. Use this option
    # with caution!
    config_accessor :use_suomifi_email do
      false
    end

    config_accessor :sp_entity_id, instance_reader: false

    # The certificate string for the application
    config_accessor :certificate, instance_reader: false

    # The private key string for the application
    config_accessor :private_key, instance_reader: false

    # The certificate file for the application
    config_accessor :certificate_file

    # The private key file for the application
    config_accessor :private_key_file

    # Defines how the session gets cleared when the OmniAuth strategy logs the
    # user out. This has been customized to preserve the flash messages in the
    # session after the session is destroyed.
    config_accessor :idp_slo_session_destroy do
      proc do |_env, session|
        flash = session["flash"]
        result = session.clear
        session["flash"] = flash if flash
        result
      end
    end

    # Extra configuration for the omniauth strategy
    config_accessor :extra do
      {}
    end

    # Allows customizing the authorization workflow e.g. for adding custom
    # workflow options or configuring an action authorizer for the
    # particular needs.
    config_accessor :workflow_configurator do
      lambda do |workflow|
        # By default, expiration is set to 0 minutes which means it will
        # never expire.
        workflow.expires_in = 0.minutes
      end
    end

    # Allows customizing parts of the authentication flow such as validating
    # the authorization data before allowing the user to be authenticated.
    config_accessor :authenticator_class do
      Decidim::Suomifi::Authentication::Authenticator
    end

    # Allows customizing how the authorization metadata gets collected from
    # the SAML attributes passed from the authorization endpoint.
    config_accessor :metadata_collector_class do
      Decidim::Suomifi::Verification::MetadataCollector
    end

    def self.configured?
      @configured
    end

    def self.configure
      @configured = true
      super
    end

    def self.authenticator_for(organization, oauth_hash)
      authenticator_class.new(organization, oauth_hash)
    end

    def self.mode
      return config.mode if config.mode
      return :production unless Rails.application.secrets.omniauth
      return :production unless Rails.application.secrets.omniauth[:suomifi]

      # Read the mode from the secrets
      secrets = Rails.application.secrets.omniauth[:suomifi]
      secrets[:mode] == "test" ? :test : :production
    end

    def self.sp_entity_id
      return config.sp_entity_id if config.sp_entity_id

      "#{application_host}/users/auth/suomifi/metadata"
    end

    def self.certificate
      return File.read(certificate_file) if certificate_file

      config.certificate
    end

    def self.private_key
      return File.read(private_key_file) if private_key_file

      config.private_key
    end

    def self.omniauth_settings
      settings = {
        mode: mode,
        scope_of_data: scope_of_data,
        sp_entity_id: sp_entity_id,
        certificate: certificate,
        private_key: private_key,
        idp_slo_session_destroy: idp_slo_session_destroy
      }
      settings.merge!(config.extra) if config.extra.is_a?(Hash)
      settings
    end

    # Used to determine the default service provider entity ID in case not
    # specifically set by the `sp_entity_id` configuration option.
    def self.application_host
      conf = Rails.application.config
      url_options = conf.action_controller.default_url_options
      url_options = conf.action_mailer.default_url_options if !url_options || !url_options[:host]
      url_options ||= {}

      host = url_options[:host]
      port = url_options[:port]
      if host.blank?
        # Default to local development environment
        host = "http://localhost"
        port ||= 3000
      end

      return "#{host}:#{port}" if port && ![80, 443].include?(port.to_i)

      host
    end
  end
end

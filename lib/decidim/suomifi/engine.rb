# frozen_string_literal: true

module Decidim
  module Suomifi
    class Engine < ::Rails::Engine
      isolate_namespace Decidim::Suomifi

      routes do
        devise_scope :user do
          # Manually map the SAML omniauth routes for Devise because the default
          # routes are mounted by core Decidim. This is because we want to map
          # these routes to the local callbacks controller instead of the
          # Decidim core.
          # See: https://git.io/fjDz1
          match(
            "/users/auth/suomifi",
            to: "omniauth_callbacks#passthru",
            as: "user_suomifi_omniauth_authorize",
            via: [:get, :post]
          )

          match(
            "/users/auth/suomifi/callback",
            to: "omniauth_callbacks#suomifi",
            as: "user_suomifi_omniauth_callback",
            via: [:get, :post]
          )
        end
      end

      initializer "decidim_suomifi.mount_routes", before: :add_routing_paths do
        # Mount the engine routes to Decidim::Core::Engine because otherwise
        # they would not get mounted properly. Note also that we need to prepend
        # the routes in order for them to override Decidim's own routes for the
        # "suomifi" authentication.
        Decidim::Core::Engine.routes.prepend do
          mount Decidim::Suomifi::Engine => "/"
        end
      end

      initializer "decidim_suomifi.setup", before: "devise.omniauth" do
        # Configure the SAML OmniAuth strategy for Devise
        ::Devise.setup do |config|
          config.omniauth(
            :suomifi,
            Decidim::Suomifi.omniauth_settings
          )
        end

        # Customized version of Devise's OmniAuth failure app in order to handle
        # the failures properly. Without this, the failure requests would end
        # up in an ActionController::InvalidAuthenticityToken exception.
        devise_failure_app = OmniAuth.config.on_failure
        OmniAuth.config.on_failure = proc do |env|
          if env["PATH_INFO"] =~ %r{^/users/auth/suomifi(/.*)?}
            env["devise.mapping"] = ::Devise.mappings[:user]
            Decidim::Suomifi::OmniauthCallbacksController.action(
              :failure
            ).call(env)
          else
            # Call the default for others.
            devise_failure_app.call(env)
          end
        end
      end

      initializer "decidim_suomifi.omniauth_provider" do
        Decidim::Suomifi::Engine.add_omniauth_provider

        # This also needs to run as a callback for the reloader because
        # otherwise the suomifi OmniAuth routes would not be added to the core
        # engine because its routes are reloaded before e.g. the to_prepare hook
        # runs in this engine. The OmniAuth provider needs to be added before
        # the core routes are reloaded.
        ActiveSupport::Reloader.to_run do
          Decidim::Suomifi::Engine.add_omniauth_provider
        end
      end

      def self.add_omniauth_provider
        # Add :suomifi to the Decidim omniauth providers
        providers = ::Decidim::User::OMNIAUTH_PROVIDERS
        unless providers.include?(:suomifi)
          providers << :suomifi
          ::Decidim::User.send(:remove_const, :OMNIAUTH_PROVIDERS)
          ::Decidim::User.const_set(:OMNIAUTH_PROVIDERS, providers)
        end
      end
    end
  end
end

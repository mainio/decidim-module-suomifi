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

          # Add the SLO and SPSLO paths to be able to pass these requests to
          # OmniAuth.
          match(
            "/users/auth/suomifi/slo",
            to: "sessions#slo",
            as: "user_suomifi_omniauth_slo",
            via: [:get, :post]
          )

          match(
            "/users/auth/suomifi/spslo",
            to: "sessions#spslo",
            as: "user_suomifi_omniauth_spslo",
            via: [:get, :post]
          )

          # Manually map the sign out path in order to control the sign out
          # flow through OmniAuth when the user signs out from the service.
          # In these cases, the user needs to be also signed out from Suomi.fi
          # which is handled by the OmniAuth strategy.
          match(
            "/users/sign_out",
            to: "sessions#destroy",
            as: "destroy_user_session",
            via: [:delete, :post]
          )

          # This is the callback route after a returning from a successful sign
          # out request through OmniAuth.
          match(
            "/users/slo_callback",
            to: "sessions#slo_callback",
            as: "slo_callback_user_session",
            via: [:get]
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
        next unless Decidim::Suomifi.configured?

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

      initializer "decidim_suomifi.mail_interceptors" do
        ActionMailer::Base.register_interceptor(
          MailInterceptors::GeneratedRecipientsInterceptor
        )
      end
    end
  end
end

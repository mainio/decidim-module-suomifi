# frozen_string_literal: true

module Decidim
  module Suomifi
    module Verification
      # This is an engine that performs user authorization.
      class Engine < ::Rails::Engine
        isolate_namespace Decidim::Suomifi::Verification

        paths["db/migrate"] = nil
        paths["lib/tasks"] = nil

        routes do
          resource :authorizations, only: [:new], as: :authorization

          root to: "authorizations#new"
        end

        initializer "decidim_suomifi.verification_workflow" do
          # We cannot use the name `:suomifi` for the verification workflow
          # because otherwise the route namespace (decidim_suomifi) would
          # conflict with the main engine controlling the authentication flows.
          # The main problem that this would bring is that the root path for
          # this engine would not be found.
          Decidim::Verifications.register_workflow(:suomifi_eid) do |workflow|
            workflow.engine = Decidim::Suomifi::Verification::Engine
            workflow.expires_in = Decidim::Suomifi.config.authorization_expiration
          end
        end

        def load_seed
          # Enable the `:suomifi_eid` authorization
          org = Decidim::Organization.first
          org.available_authorizations << :suomifi_eid
          org.save!
        end
      end
    end
  end
end

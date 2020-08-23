# frozen_string_literal: true

module Decidim
  module Suomifi
    module Verification
      class AuthorizationsController < ::Decidim::ApplicationController
        skip_before_action :store_current_location

        def new
          # Do not enforce the permission here because it would cause
          # re-authorizations not to work as the authorization already exists.
          # In case the user wants to re-authorize themselves, they can just
          # hit this endpoint again.
          redirect_to decidim.user_suomifi_omniauth_authorize_path
        end
      end
    end
  end
end

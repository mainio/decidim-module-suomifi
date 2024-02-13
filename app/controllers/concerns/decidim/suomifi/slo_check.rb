# frozen_string_literal: true

module Decidim
  module Suomifi
    # Logic to check that the user hasn't signed out through the SLO page
    # initiated by some other service using the same session.
    module SloCheck
      extend ActiveSupport::Concern

      included do
        before_action :ensure_suomifi_session!
      end

      private

      def ensure_suomifi_session!
        return unless user_signed_in?
        return unless session["decidim-suomifi.signed_in"]
        return unless session["saml_uid"]
        return unless session["saml_session_index"]

        suomifi_session = Decidim::Suomifi::Session.where.not(ended_at: nil).find_by(
          saml_uid: session["saml_uid"],
          saml_session_index: session["saml_session_index"]
        )
        return unless suomifi_session

        # The session has ended through the Suomi.fi SLO
        suomifi_session.destroy!

        # Logout the user through warden
        scope = ::Devise::Mapping.find_scope!(:user)
        warden = request.env["warden"]
        warden.logout(scope)
        warden.clear_strategies_cache!(scope: scope)

        # Clear the current session
        session.clear

        # Reset the variables referring to the current user
        @current_user = nil
        @real_user = nil

        # Flash and redirect
        flash[:warning] = t("session_ended", scope: "decidim.suomifi.slo_check")
        redirect_to "/"
      end
    end
  end
end

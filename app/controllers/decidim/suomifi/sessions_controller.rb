# frozen_string_literal: true

module Decidim
  module Suomifi
    class SessionsController < ::Decidim::Devise::SessionsController
      def destroy
        # In case the user is signed in through Suomi.fi, redirect them through
        # the SPSLO flow.
        if session.delete("decidim-suomifi.signed_in")
          # These session variables get destroyed along with the user's active
          # session. They are needed for the SLO request.
          saml_uid = session["saml_uid"]
          saml_session_index = session["saml_session_index"]

          # End the local user session.
          signed_out = (::Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))

          # Store the SAML parameters for the SLO request utilized by
          # omniauth-saml. These are used to generate a valid SLO request.
          session["saml_uid"] = saml_uid
          session["saml_session_index"] = saml_session_index
          session["saml_redirect_url"] = request.params["redirect_url"]

          # Generate the SLO redirect path and parameters.
          relay = slo_callback_user_session_path
          relay += "?success=1" if signed_out
          params = "?RelayState=#{CGI.escape(relay)}"

          return redirect_to user_suomifi_omniauth_spslo_path + params
        end

        # Otherwise, continue normally
        super
      end

      # This can be removed after the following PR is merged to the core:
      # https://github.com/decidim/decidim/pull/5823
      def sign_out(resource_or_scope = nil)
        result = super

        # Because of this change in the core, we have to manually clear the
        # `@real_user` instance variable after sign out:
        # https://github.com/decidim/decidim/pull/5533
        @real_user = nil

        result
      end

      def slo
        # This is handled already by omniauth
        redirect_to decidim.root_path
      end

      def spslo
        # This is handled already by omniauth
        redirect_to decidim.root_path
      end

      def slo_callback
        set_flash_message! :notice, :signed_out if params[:success] == "1"

        redirect_to after_sign_out_path_for(resource_name)
      end

      def after_sign_out_path_for(_resource_name)
        redirect_to = session.delete("saml_redirect_url")
        return redirect_to if redirect_to.present? && redirect_to.match?(%r{\A/.*\z})

        "/"
      end
    end
  end
end

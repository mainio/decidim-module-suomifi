# frozen_string_literal: true

module Decidim
  module Suomifi
    class OmniauthCallbacksController < ::Decidim::Devise::OmniauthRegistrationsController
      # Make the view helpers available needed in the views
      helper Decidim::Suomifi::Engine.routes.url_helpers
      helper_method :omniauth_registrations_path

      skip_before_action :verify_authenticity_token, only: [:suomifi, :failure]
      skip_after_action :verify_same_origin_request, only: [:suomifi, :failure]

      # This is called always after the user returns from the authentication
      # flow from the Suomi.fi identity provider.
      def suomifi
        if user_signed_in?
          # The user is most likely returning from an authorization request
          # because they are already signed in. In this case, add the
          # authorization and redirect the user back to the authorizations view.

          # Make sure the user has an identity created in order to aid future
          # Suomi.fi sign ins.
          identity = current_user.identities.find_by(
            organization: current_organization,
            provider: oauth_data[:provider],
            uid: user_identifier
          )
          unless identity
            # Check that the identity is not already bound to another user.
            id = Decidim::Identity.find_by(
              organization: current_organization,
              provider: oauth_data[:provider],
              uid: user_identifier
            )
            return fail_authorize(:identity_bound_to_other_user) if id

            current_user.identities.create!(
              organization: current_organization,
              provider: oauth_data[:provider],
              uid: user_identifier
            )
          end

          # Add the authorization for the user
          return fail_authorize unless authorize_user(current_user)

          # Show the success message and redirect back to the authorizations
          flash[:notice] = t(
            "authorizations.create.success",
            scope: "decidim.suomifi.verification"
          )
          return redirect_to decidim_verifications.authorizations_path
        end

        # Normal authentication request, proceed with Decidim's internal logic.
        send(:create)
      end

      def failure
        strategy = failed_strategy
        saml_response = strategy.response_object
        return super if !strategy || saml_response.nil?

        # In case we want more info about the returned status codes, use the
        # code below.
        #
        # Status codes:
        #   Requester = A problem with the request OR the user cancelled the
        #               request at the identity provider.
        #   Responder = The handling of the request failed.
        #   VersionMismatch = Wrong version in the request.
        #
        # Additional state codes:
        #   AuthnFailed = The authentication failed OR the user cancelled
        #                 the process at the identity provider.
        #   RequestDenied = The authenticating endpoint (which the
        #                   identity provider redirects to) rejected the
        #                   authentication.
        # if !saml_response.send(:validate_success_status) && !saml_response.status_code.nil?
        #   codes = saml_response.status_code.split(" | ").map do |full_code|
        #     full_code.split(":").last
        #   end
        # end

        # Some extra validation checks
        validations = [
          # The success status validation fails in case the response status
          # code is something else than "Success". This is most likely because
          # of one the reasons explained above. In general there are few
          # possible explanations for this:
          # 1. The user cancelled the request and returned to the service.
          # 2. The underlying identity service the IdP redirects to rejected
          #    the request for one reason or another. E.g. the user cancelled
          #    the request at the identity service.
          # 3. There is some technical problem with the identity provider
          #    service or the XML request sent to there is malformed.
          :success_status,
          # Checks if the local session should be expired, i.e. if the user
          # took too long time to go through the authorization endpoint.
          :session_expiration,
          # The NotBefore and NotOnOrAfter conditions failed, i.e. whether the
          # request is handled within the allowed timeframe by the IdP.
          :conditions
        ]
        validations.each do |key|
          next if saml_response.send("validate_#{key}")

          flash[:alert] = t(".#{key}")
          return redirect_to after_omniauth_failure_path_for(resource_name)
        end

        super
      end

      # This is overridden method from the Devise controller helpers
      # This is called when the user is successfully authenticated which means
      # that we also need to add the authorization for the user automatically
      # because a succesful Suomi.fi authentication means the user has been
      # successfully authorized as well.
      def sign_in_and_redirect(resource_or_scope, *args)
        # Add authorization for the user
        if resource_or_scope.is_a?(::Decidim::User)
          return fail_authorize unless authorize_user(resource_or_scope)
        end

        super
      end

      private

      def authorize_user(user)
        authorization = Decidim::Authorization.find_by(
          name: "suomifi_eid",
          unique_id: user_signature
        )
        if authorization
          return nil if authorization.user != user
        else
          authorization = Decidim::Authorization.find_or_initialize_by(
            name: "suomifi_eid",
            user: user
          )
        end

        authorization.attributes = {
          unique_id: user_signature,
          metadata: authorization_metadata
        }
        authorization.save!

        # This will update the "granted_at" timestamp of the authorization which
        # will postpone expiration on re-authorizations in case the
        # authorization is set to expire (by default it will not expire).
        authorization.grant!

        authorization
      end

      def fail_authorize(failure_message_key = :already_authorized)
        flash[:alert] = t(
          "failure.#{failure_message_key}",
          scope: "decidim.suomifi.omniauth_callbacks"
        )
        redirect_to stored_location_for(resource || :user) || decidim.root_path
      end

      # Data that is stored against the authorization "permanently" (i.e. as
      # long as the authorization is valid).
      def authorization_metadata
        hetu = Henkilotunnus::Hetu.new(
          saml_attributes[:national_identification_number]
        )
        # In case the HETU was not sent by Suomi.fi, it will be empty and
        # therefore invalid and will not have the gender information. With empty
        # HETU, `Henkilotunnus::Hetu` would otherwise report "female" as the
        # gender which would not be correct.
        gender = nil
        date_of_birth = nil
        if hetu.valid?
          gender = hetu.male? ? "m" : "f"
          # `.to_s` returns an ISO 8601 formatted string (YYYY-MM-DD for dates)
          date_of_birth = hetu.date_of_birth.to_s
        elsif saml_attributes[:eidas_date_of_birth]
          # xsd:date (YYYY-MM_DD)
          date_of_birth = saml_attributes[:eidas_date_of_birth]
        end

        postal_code_permanent = true
        postal_code = saml_attributes[:permanent_domestic_address_postal_code]
        unless postal_code
          postal_code_permanent = false
          postal_code = saml_attributes[:temporary_domestic_address_postal_code]
        end

        first_name = saml_attributes[:first_names]
        last_name = saml_attributes[:last_name]
        given_name = saml_attributes[:given_name]

        eidas = false
        if saml_attributes[:eidas_person_identifier]
          eidas = true
          first_name = saml_attributes[:eidas_first_names]
          last_name = saml_attributes[:eidas_family_name]
        end

        {
          eidas: eidas,
          gender: gender,
          date_of_birth: date_of_birth,
          pin_digest: person_identifier_digest,
          # The first name will contain all first names of the person
          first_name: first_name,
          # The given name is the primary first name of the person, also known
          # as "calling name" (kutsumanimi).
          given_name: given_name,
          last_name: last_name,
          # The municipality number, see:
          # http://tilastokeskus.fi/meta/luokitukset/kunta/001-2017/index.html
          municipality: saml_attributes[:home_municipality_number],
          municipality_name: saml_attributes[:home_municipality_name_fi],
          postal_code: postal_code,
          permanent_address: postal_code_permanent
        }
      end

      # Needs to be specifically defined because the core engine routes are not
      # all properly loaded for the view and this helper method is needed for
      # defining the omniauth registration form's submit path.
      def omniauth_registrations_path(resource)
        Decidim::Core::Engine.routes.url_helpers.omniauth_registrations_path(resource)
      end

      # Private: Create form params from omniauth hash
      # Since we are using trusted omniauth data we are generating a valid signature.
      def user_params_from_oauth_hash
        return nil if oauth_data.empty?
        return nil if saml_attributes.empty?
        return nil if user_identifier.blank?

        {
          provider: oauth_data[:provider],
          uid: user_identifier,
          name: user_full_name,
          # The nickname is automatically "parametrized" by Decidim core from
          # the name string, i.e. it will be in correct format.
          nickname: user_full_name,
          oauth_signature: user_signature,
          avatar_url: oauth_data[:info][:image],
          raw_data: oauth_hash
        }
      end

      def user_full_name
        return oauth_data[:info][:name] if oauth_data[:info][:name]

        @user_full_name ||= begin
          first_name = begin
            saml_attributes[:given_name] ||
              saml_attributes[:first_names] ||
              saml_attributes[:eidas_first_names]
          end
          last_name = begin
            saml_attributes[:last_name] ||
              saml_attributes[:eidas_family_name]
          end

          "#{first_name} #{last_name}"
        end
      end

      def user_signature
        @user_signature ||= OmniauthRegistrationForm.create_signature(
          oauth_data[:provider],
          user_identifier
        )
      end

      # See the omniauth-suomi gem's notes about the UID. It should be always
      # unique per person as long as it can be determined from the user's data.
      # This consists of one of the following in this order:
      # - The person's electronic identifier (SATU ID, sähköinen asiointitunnus)
      # - The person's personal identifier (HETU ID, henkilötunnus) in hashed
      #   format
      # - The person's eIDAS personal identifier (eIDAS PID) in hashed format
      # - The SAML NameID in the SAML response in case no unique personal data
      #   is available as defined above
      def user_identifier
        @user_identifier ||= oauth_data[:uid]
      end

      # Digested format of the person's identifier unique to the person. The
      # digested format is used because the undigested format may hold personal
      # sensitive information about the user and may require special care
      # regarding the privacy policy.
      # These will still be unique hashes bound to the person's identification
      # number.
      def person_identifier_digest
        @person_identifier_digest ||= begin
          prefix = nil
          pin = nil

          if saml_attributes[:national_identification_number]
            prefix = "FI"
            pin = saml_attributes[:national_identification_number]
          elsif saml_attributes[:eidas_person_identifier]
            prefix = "EIDAS"
            pin = saml_attributes[:eidas_person_identifier]
          end

          if prefix && pin
            Digest::MD5.hexdigest(
              "#{prefix}:#{pin}:#{Rails.application.secrets.secret_key_base}"
            )
          end
        end
      end

      def verified_email
        @verified_email ||= begin
          if saml_attributes[:email]
            saml_attributes[:email]
          elsif Decidim::Suomifi.auto_email_domain
            domain = Decidim::Suomifi.auto_email_domain
            "suomifi-#{person_identifier_digest}@#{domain}"
          end
        end
      end

      def saml_attributes
        @saml_attributes ||= oauth_hash[:extra][:saml_attributes]
      end
    end
  end
end

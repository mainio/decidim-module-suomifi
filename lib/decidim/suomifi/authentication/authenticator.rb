# frozen_string_literal: true

module Decidim
  module Suomifi
    module Authentication
      class Authenticator
        include ActiveModel::Validations

        def initialize(organization, oauth_hash)
          @organization = organization
          @oauth_hash = oauth_hash
        end

        def verified_email
          @verified_email ||=
            if Decidim::Suomifi.use_suomifi_email && saml_attributes[:email]
              saml_attributes[:email]
            else
              domain = Decidim::Suomifi.auto_email_domain || organization.host
              "suomifi-#{person_identifier_digest}@#{domain}"
            end
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

        def validate!
          raise ValidationError, "No SAML data provided" if saml_attributes.blank?

          data_blank = saml_attributes.all? { |_k, val| val.blank? }
          raise ValidationError, "Invalid SAML data" if data_blank
          raise ValidationError, "Invalid person dentifier" if person_identifier_digest.blank?

          true
        end

        def identify_user!(user)
          identity = user.identities.find_by(
            organization: organization,
            provider: oauth_data[:provider],
            uid: user_identifier
          )
          return identity if identity

          # Check that the identity is not already bound to another user.
          id = Decidim::Identity.find_by(
            organization: organization,
            provider: oauth_data[:provider],
            uid: user_identifier
          )

          raise IdentityBoundToOtherUserError if id

          user.identities.create!(
            organization: organization,
            provider: oauth_data[:provider],
            uid: user_identifier
          )
        end

        def authorize_user!(user)
          authorization = Decidim::Authorization.find_by(
            name: "suomifi_eid",
            unique_id: user_signature
          )
          if authorization
            raise AuthorizationBoundToOtherUserError if authorization.user != user
          else
            authorization = Decidim::Authorization.find_or_initialize_by(
              name: "suomifi_eid",
              user: user
            )
          end

          authorization.pseudonymized_pin = person_identifier_digest if authorization.pseudonymized_pin.blank?
          authorization.attributes = {
            unique_id: user_signature,
            metadata: authorization_metadata
          }
          authorization.save!

          # This will update the "granted_at" timestamp of the authorization
          # which will postpone expiration on re-authorizations in case the
          # authorization is set to expire (by default it will not expire).
          authorization.grant!

          authorization
        end

        protected

        attr_reader :organization, :oauth_hash

        def oauth_data
          @oauth_data ||= oauth_hash.slice(:provider, :uid, :info)
        end

        def saml_attributes
          @saml_attributes ||= oauth_hash[:extra][:saml_attributes]
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

        # Create a unique signature for the user that will be used for the
        # granted authorization.
        def user_signature
          @user_signature ||= ::Decidim::OmniauthRegistrationForm.create_signature(
            oauth_data[:provider],
            user_identifier
          )
        end

        def user_full_name
          return oauth_data[:info][:name] if oauth_data[:info][:name]

          @user_full_name ||= begin
            first_name =
              saml_attributes[:given_name] ||
              saml_attributes[:first_names] ||
              saml_attributes[:eidas_first_names]
            last_name =
              saml_attributes[:last_name] ||
              saml_attributes[:eidas_family_name]

            "#{first_name} #{last_name}"
          end
        end

        def metadata_collector
          @metadata_collector ||= ::Decidim::Suomifi::Verification::Manager.metadata_collector_for(
            saml_attributes
          )
        end

        # Data that is stored against the authorization "permanently" (i.e. as
        # long as the authorization is valid).
        def authorization_metadata
          metadata_collector.metadata
        end

        # The digest that is created from the person identifier.
        def person_identifier_digest
          metadata_collector.person_identifier_digest
        end
      end
    end
  end
end

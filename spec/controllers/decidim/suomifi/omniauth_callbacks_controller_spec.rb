# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Suomifi
    # Tests the controller as well as the underlying SAML integration that the
    # OmniAuth strategy is correctly loading the attribute values from the SAML
    # response. Note that this is why we are using the `:request` type instead
    # of `:controller`, so that we get the OmniAuth middleware applied to the
    # requests and the Suomi.fi OmniAuth strategy to handle our generated
    # SAMLResponse.
    describe OmniauthCallbacksController, type: :request do
      let(:organization) { create(:organization) }

      # For testing with signed in user
      let(:confirmed_user) do
        create(:user, :confirmed, organization: organization)
      end

      before do
        # Make the time validation of the SAML response work properly
        allow(Time).to receive(:now).and_return(
          Time.utc(2019, 8, 10, 13, 5, 0)
        )

        # Set the correct host
        host! organization.host
      end

      describe "GET suomifi" do
        let(:saml_attributes_base) do
          {
            cn: "Mainio Matti Martti",
            sn: "Mainio",
            FirstName: "Matti Martti",
            givenName: "Matti",
            displayName: "Matti Mainio",
            nationalIdentificationNumber: "220185-765L",
            VakinainenKotimainenLahiosoitePostitoimipaikkaS: "HELSINKI",
            VakinainenKotimainenLahiosoitePostinumero: "00210",
            KotikuntaKuntaS: "Helsinki",
            KotikuntaKuntaR: "Helsingfors",
            KotikuntaKuntanumero: "091"
          }
        end
        let(:saml_attributes) { {} }
        let(:saml_response) do
          attrs = saml_attributes_base.merge(saml_attributes)
          resp_xml = generate_saml_response(attrs)
          Base64.strict_encode64(resp_xml)
        end

        it "creates a new user record with the returned SAML attributes" do
          omniauth_callback_get

          user = User.last

          expect(user.name).to eq("Matti Mainio")
          expect(user.nickname).to eq("matti_mainio")

          authorization = Authorization.find_by(
            user: user,
            name: "suomifi_eid"
          )
          expect(authorization).not_to be_nil

          pin_digest = Digest::MD5.hexdigest(
            "FI:220185-765L:#{Rails.application.secrets.secret_key_base}"
          )
          expect(authorization.metadata).to include(
            "eidas" => false,
            "gender" => "m",
            "last_name" => "Mainio",
            "first_name" => "Matti Martti",
            "given_name" => "Matti",
            "pin_digest" => pin_digest,
            "postal_code" => "00210",
            "permanent_address" => true,
            "date_of_birth" => "1985-01-22",
            "municipality" => "091",
            "municipality_name" => "Helsinki"
          )
        end

        # Decidim core would want to redirect to the verifications path on the
        # first sign in but we don't want that to happen as the user is already
        # authorized during the sign in process.
        it "redirects to the root path by default after a successful registration and first sign in" do
          omniauth_callback_get

          user = User.last

          expect(user.sign_in_count).to eq(1)
          expect(response).to redirect_to("/")
        end

        context "when the session has a pending redirect" do
          let(:after_sign_in_path) { "/processes" }

          before do
            # Do a mock request in order to create a session
            get "/"
            request.session["user_return_to"] = after_sign_in_path
          end

          it "redirects to the stored location by default after a successful registration and first sign in" do
            omniauth_callback_get(
              env: {
                "rack.session" => request.session,
                "rack.session.options" => request.session.options
              }
            )

            user = User.last

            expect(user.sign_in_count).to eq(1)
            expect(response).to redirect_to("/processes")
          end
        end

        context "when the person is a woman" do
          let(:saml_attributes) do
            {
              cn: "Mainio Marja Mirja",
              sn: "Mainio",
              FirstName: "Marja Mirja",
              givenName: "Marja",
              displayName: "Marja Mainio",
              nationalIdentificationNumber: "150785-5843"
            }
          end

          it "creates a new user record with the returned SAML attributes" do
            omniauth_callback_get

            user = User.last

            expect(user.name).to eq("Marja Mainio")
            expect(user.nickname).to eq("marja_mainio")

            authorization = Authorization.find_by(
              user: user,
              name: "suomifi_eid"
            )
            expect(authorization).not_to be_nil

            expect(authorization.metadata).to include(
              "gender" => "f",
              "last_name" => "Mainio",
              "first_name" => "Marja Mirja",
              "given_name" => "Marja",
              "date_of_birth" => "1985-07-15"
            )
          end
        end

        context "when no email is returned from the IdP" do
          it "creates a new user record with auto-generated email" do
            omniauth_callback_get

            user = User.last

            expect(user.email).to match(/suomifi-[a-z0-9]{32}@1.lvh.me/)
          end
        end

        context "when email is returned from the IdP" do
          let(:saml_attributes) { { mail: "matti.mainio@test.fi" } }

          it "creates a new user record with the returned email" do
            omniauth_callback_get

            user = User.last

            expect(user.email).to eq("matti.mainio@test.fi")
          end
        end

        context "when email is returned from the IdP that matches existing user" do
          let(:saml_attributes) { { mail: confirmed_user.email } }

          it "hijacks the account for the returned email" do
            omniauth_callback_get

            authorization = Authorization.find_by(
              user: confirmed_user,
              name: "suomifi_eid"
            )
            expect(authorization).not_to be_nil
            expect(authorization.metadata).to include(
              "gender" => "m",
              "last_name" => "Mainio",
              "first_name" => "Matti Martti",
              "given_name" => "Matti",
              "postal_code" => "00210",
              "permanent_address" => true,
              "date_of_birth" => "1985-01-22",
              "municipality" => "091",
              "municipality_name" => "Helsinki"
            )

            warden = request.env["warden"]
            current_user = warden.authenticate(scope: :user)
            expect(current_user).to eq(confirmed_user)
          end
        end

        context "when returning from an eIDAS identification service" do
          let(:saml_attributes_base) do
            # With eIDAS authentications, these are the only details transmitted
            # about the user. The population information system query will not
            # be made with eIDAS authentications.
            {
              PersonIdentifier: "28493196Z", # Spanish DNI
              FirstName: "Felipe Guerrero",
              FamilyName: "Torres",
              DateOfBirth: "1985-01-22"
            }
          end

          it "creates a new user record with the returned SAML attributes" do
            omniauth_callback_get

            user = User.last

            expect(user.name).to eq("Felipe Guerrero Torres")
            expect(user.nickname).to eq("felipe_guerrero_torr")

            authorization = Authorization.find_or_initialize_by(
              user: user,
              name: "suomifi_eid"
            )
            expect(authorization).not_to be_nil

            pin_digest = Digest::MD5.hexdigest(
              "EIDAS:28493196Z:#{Rails.application.secrets.secret_key_base}"
            )
            expect(authorization.metadata).to include(
              "eidas" => true,
              "gender" => nil,
              "last_name" => "Torres",
              "first_name" => "Felipe Guerrero",
              "pin_digest" => pin_digest,
              "date_of_birth" => "1985-01-22"
            )
          end
        end

        context "when the user is already signed in" do
          before do
            sign_in confirmed_user
          end

          it "adds the authorization to the signed in user" do
            omniauth_callback_get

            expect(confirmed_user.name).not_to eq("Matti Mainio")
            expect(confirmed_user.nickname).not_to eq("matti_mainio")

            authorization = Authorization.find_by(
              user: confirmed_user,
              name: "suomifi_eid"
            )
            expect(authorization).not_to be_nil

            pin_digest = Digest::MD5.hexdigest(
              "FI:220185-765L:#{Rails.application.secrets.secret_key_base}"
            )
            expect(authorization.metadata).to include(
              "eidas" => false,
              "gender" => "m",
              "last_name" => "Mainio",
              "first_name" => "Matti Martti",
              "given_name" => "Matti",
              "pin_digest" => pin_digest,
              "postal_code" => "00210",
              "permanent_address" => true,
              "date_of_birth" => "1985-01-22",
              "municipality" => "091",
              "municipality_name" => "Helsinki"
            )
          end

          it "redirects to the root path" do
            omniauth_callback_get

            expect(response).to redirect_to("/")
          end

          context "when the session has a pending redirect" do
            let(:after_sign_in_path) { "/processes" }

            before do
              # Do a mock request in order to create a session
              get "/"
              request.session["user_return_to"] = after_sign_in_path
            end

            it "redirects to the stored location" do
              omniauth_callback_get(
                env: {
                  "rack.session" => request.session,
                  "rack.session.options" => request.session.options
                }
              )

              expect(response).to redirect_to("/processes")
            end
          end

          context "when user has set remember me" do
            before do
              confirmed_user.remember_created_at = Time.current
              confirmed_user.save!
            end

            it "forgets the user" do
              omniauth_callback_get
              expect(Decidim::User.find(confirmed_user.id).remember_created_at).to eq(nil)
            end
          end
        end

        context "when the user is already signed in and authorized" do
          let!(:authorization) do
            identifier_digest = "FIHETU:" + Digest::MD5.hexdigest(
              "FI:220185-765L:#{Rails.application.secrets.secret_key_base}"
            )
            signature = OmniauthRegistrationForm.create_signature(
              :suomifi,
              identifier_digest
            )
            authorization = Decidim::Authorization.create(
              user: confirmed_user,
              name: "suomifi_eid",
              attributes: {
                unique_id: signature,
                metadata: {}
              }
            )
            authorization.save!
            authorization.grant!
            authorization
          end

          before do
            sign_in confirmed_user
          end

          it "updates the existing authorization" do
            omniauth_callback_get

            # Check that the user record was NOT updated
            expect(confirmed_user.name).not_to eq("Matti Mainio")
            expect(confirmed_user.nickname).not_to eq("matti_mainio")

            # Check that the authorization is the same one
            authorizations = Authorization.where(
              user: confirmed_user,
              name: "suomifi_eid"
            )
            expect(authorizations.count).to eq(1)
            expect(authorizations.first).to eq(authorization)

            # Check that the metadata was updated
            pin_digest = Digest::MD5.hexdigest(
              "FI:220185-765L:#{Rails.application.secrets.secret_key_base}"
            )
            expect(authorizations.first.metadata).to include(
              "eidas" => false,
              "gender" => "m",
              "last_name" => "Mainio",
              "first_name" => "Matti Martti",
              "given_name" => "Matti",
              "pin_digest" => pin_digest,
              "postal_code" => "00210",
              "permanent_address" => true,
              "date_of_birth" => "1985-01-22",
              "municipality" => "091",
              "municipality_name" => "Helsinki"
            )
          end
        end

        context "when another user is already identified with the same identity" do
          let(:another_user) do
            create(:user, :confirmed, organization: organization)
          end

          before do
            identifier_digest = "FIHETU:" + Digest::MD5.hexdigest(
              "FI:220185-765L:#{Rails.application.secrets.secret_key_base}"
            )
            another_user.identities.create!(
              organization: organization,
              provider: "suomifi",
              uid: identifier_digest
            )

            # Sign in the confirmed user
            sign_in confirmed_user
          end

          it "prevents the authorization with correct error message" do
            omniauth_callback_get

            authorization = Authorization.find_by(
              user: confirmed_user,
              name: "suomifi_eid"
            )
            expect(authorization).to be_nil
            expect(response).to redirect_to("/users/auth/suomifi/spslo?RelayState=%2F")
            expect(flash[:alert]).to eq(
              "Another user has already been identified using this identity. Please sign out and sign in again directly using Suomi.fi."
            )
          end
        end

        context "when no SAML attributes are returned from the IdP" do
          let(:saml_attributes_base) { {} }

          it "prevents the authentication with correct error message" do
            omniauth_callback_get

            expect(User.count).to eq(0)
            expect(Authorization.count).to eq(0)
            expect(Identity.count).to eq(0)
            expect(flash[:alert]).to eq(
              "You cannot be authenticated through Suomi.fi."
            )
          end
        end

        context "when another user is already authorized with the same identity" do
          let(:another_user) do
            create(:user, :confirmed, organization: organization)
          end

          before do
            identifier_digest = "FIHETU:" + Digest::MD5.hexdigest(
              "FI:220185-765L:#{Rails.application.secrets.secret_key_base}"
            )
            signature = OmniauthRegistrationForm.create_signature(
              :suomifi,
              identifier_digest
            )
            authorization = Decidim::Authorization.create(
              user: another_user,
              name: "suomifi_eid",
              attributes: {
                unique_id: signature,
                metadata: {}
              }
            )
            authorization.save!
            authorization.grant!

            # Sign in the confirmed user
            sign_in confirmed_user
          end

          it "prevents the authorization with correct error message" do
            omniauth_callback_get

            authorization = Authorization.find_by(
              user: confirmed_user,
              name: "suomifi_eid"
            )
            expect(authorization).to be_nil
            expect(response).to redirect_to("/users/auth/suomifi/spslo?RelayState=%2F")
            expect(flash[:alert]).to eq(
              "Another user has already authorized themselves with the same identity."
            )
          end
        end

        context "with response handling being outside of the allowed timeframe" do
          let(:saml_response) do
            attrs = saml_attributes_base.merge(saml_attributes)
            resp_xml = generate_saml_response(attrs) do |doc|
              conditions_node = doc.root.at_xpath(
                "//saml2:Assertion//saml2:Conditions",
                saml2: "urn:oasis:names:tc:SAML:2.0:assertion"
              )
              conditions_node["NotBefore"] = "2010-08-10T13:03:46.695Z"
              conditions_node["NotOnOrAfter"] = "2010-08-10T13:03:46.695Z"
            end
            Base64.strict_encode64(resp_xml)
          end

          it "calls the failure endpoint" do
            omniauth_callback_get

            expect(User.last).to be_nil
            expect(response).to redirect_to("/users/sign_in")
            expect(flash[:alert]).to eq(
              "The authentication request was not handled within an allowed timeframe. Please try again."
            )
          end
        end

        context "with authentication session expired" do
          let(:saml_response) do
            attrs = saml_attributes_base.merge(saml_attributes)
            resp_xml = generate_saml_response(attrs) do |doc|
              authn_node = doc.root.at_xpath(
                "//saml2:Assertion//saml2:AuthnStatement",
                saml2: "urn:oasis:names:tc:SAML:2.0:assertion"
              )
              authn_node["SessionNotOnOrAfter"] = "2010-08-10T13:03:46.695Z"
            end
            Base64.strict_encode64(resp_xml)
          end

          it "calls the failure endpoint" do
            omniauth_callback_get

            expect(User.last).to be_nil
            expect(response).to redirect_to("/users/sign_in")
            expect(flash[:alert]).to eq(
              "Authentication session expired. Please try again."
            )
          end
        end

        context "with failed authentication" do
          let(:saml_response) do
            resp_xml = saml_response_from_file("failed_request.xml")
            Base64.strict_encode64(resp_xml)
          end

          it "calls the failure endpoint" do
            omniauth_callback_get

            expect(User.last).to be_nil
            expect(response).to redirect_to("/users/sign_in")
            expect(flash[:alert]).to eq(
              "Authentication failed or cancelled. Please try again."
            )
          end
        end

        def omniauth_callback_get(env: nil)
          request_args = { params: { SAMLResponse: saml_response } }
          request_args[:env] = env if env

          # Call the endpoint with the SAML response
          get "/users/auth/suomifi/callback", **request_args
        end
      end

      def generate_saml_response(attributes = {})
        saml_response_from_file("saml_response_decrypted_unsigned.xml") do |doc|
          root_element = doc.root
          statements_node = root_element.at_xpath(
            "//saml2:Assertion//saml2:AttributeStatement",
            saml2: "urn:oasis:names:tc:SAML:2.0:assertion"
          )

          ::Devise.omniauth_configs[:suomifi].strategy[:possible_request_attributes].each do |attr|
            key = attr[:friendly_name].to_sym
            value = attributes[key]
            next unless value

            attr_element = Nokogiri::XML::Node.new "saml2:Attribute", doc
            attr_element["FriendlyName"] = attr[:friendly_name]
            attr_element["Name"] = attr[:name]
            attr_element["NameFormat"] = attr[:name_format]
            attr_element.add_child("<saml2:AttributeValue>#{value}</saml2:AttributeValue>")

            statements_node.add_child(attr_element)
          end

          yield doc if block_given?
        end
      end

      def saml_response_from_file(file)
        filepath = file_fixture(file)
        file_io = IO.read(filepath)
        doc = Nokogiri::XML::Document.parse(file_io)

        yield doc if block_given?

        sign_xml(doc.to_s)
      end

      def sign_xml(xml_string)
        cs = Decidim::Suomifi::Test::Runtime.cert_store
        OmniAuth::Suomifi::Test::Utility.encrypted_signed_xml_from_string(
          xml_string,
          certificate: cs.certificate,
          sign_certificate: cs.sign_certificate,
          sign_private_key: cs.sign_private_key
        )
      end
    end
  end
end

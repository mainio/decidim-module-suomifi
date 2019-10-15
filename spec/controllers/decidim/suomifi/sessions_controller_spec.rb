# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Suomifi
    # Tests the session destroying functionality with the Suomi.fi module.
    # Note that this is why we are using the `:request` type instead
    # of `:controller`, so that we get the OmniAuth middleware applied to the
    # requests and the Suomi.fi OmniAuth strategy to handle endpoints. Another
    # reason is to test the sign out path override.
    describe SessionsController, type: :request do
      let(:organization) { create(:organization) }

      # For testing with signed in user
      let(:confirmed_user) do
        create(:user, :confirmed, organization: organization)
      end

      before do
        # Set the correct host
        host! organization.host
      end

      describe "POST destroy" do
        before do
          sign_in confirmed_user
        end

        context "when there is no active Suomi.fi sign in" do
          it "signs out the user normally" do
            post "/users/sign_out"

            expect(response).to redirect_to("/")
            expect(controller.current_user).to be_nil
          end
        end

        context "when there is an active Suomi.fi sign in" do
          let(:session) { {} }

          before do
            # rubocop:disable RSpec/AnyInstance
            allow_any_instance_of(described_class).to receive(:session).and_return(session)
            # rubocop:enable RSpec/AnyInstance

            allow(session).to receive(:delete).with(
              "decidim-suomifi.signed_in"
            ).and_return(true)
          end

          it "signs out the user through the Suomi.fi SLO" do
            post "/users/sign_out"

            redirect_path = CGI.escape("/users/slo_callback?success=1")
            expect(response).to redirect_to("/users/auth/suomifi/spslo?RelayState=#{redirect_path}")
            expect(controller.current_user).to be_nil
          end
        end
      end

      describe "POST slo" do
        let(:saml_response) do
          resp_xml = saml_response_from_file("saml_logout_response.xml")
          Base64.strict_encode64(resp_xml)
        end

        let(:saml_request) do
          resp_xml = saml_response_from_file("saml_logout_request.xml")
          Base64.strict_encode64(resp_xml)
        end

        it "responds successfully to a SAML response" do
          get "/users/auth/suomifi/slo", params: { SAMLResponse: saml_response }

          expect(response).to be_redirect
          expect(response.location).to eq("/")
        end

        it "responds successfully to a SAML request" do
          session = {
            "saml_transaction_id" => "_274a0148-44ad-4238-bdb0-e56c971ae3bc",
            "saml_uid" => "AAdzZWNyZXQxfxVUqsT8k/OSMQF/s80N/8TyMb5MERaTUMrYtjpqQV/yStP+CEUegeoHqAVnB9LLOEz2XkE5ZS09VT/4FoAVyonc1z8p5TYIAQI1Hi4wAzINh7OTA6szITMUwP5GfFkW7lGQ0avmRSsr3LODiNGC1zDguiSTX0DtQ9Uq5kQ5nYLz+rJO"
          }

          # rubocop:disable RSpec/AnyInstance
          allow_any_instance_of(::OmniAuth::Strategies::Suomifi).to receive(:session).and_return(session)
          # rubocop:enable RSpec/AnyInstance

          get "/users/auth/suomifi/slo", params: { SAMLRequest: saml_request }

          expect(response).to be_redirect
          expect(response.location).to match %r{https://testi.apro.tunnistus.fi/idp/profile/SAML2/Redirect/SLO}
        end
      end

      describe "POST spslo" do
        it "signs out the user through the Suomi.fi SLO" do
          post "/users/auth/suomifi/spslo"

          expect(response).to be_redirect
          expect(response.location).to match %r{https://testi.apro.tunnistus.fi/idp/profile/SAML2/Redirect/SLO}
        end
      end

      describe "GET slo_callback" do
        it "redirects the user to after sign in path" do
          get "/users/slo_callback"

          expect(response).to redirect_to("/")
          expect(flash[:notice]).to be_nil
        end

        context "with the success flag" do
          it "redirects the user to after sign in path and sets a notice" do
            get "/users/slo_callback", params: { success: "1" }

            expect(response).to redirect_to("/")
            expect(flash[:notice]).to eq("Signed out successfully.")
          end
        end
      end

      def saml_response_from_file(file)
        filepath = file_fixture(file)
        file_io = IO.read(filepath)
        doc = Nokogiri::XML::Document.parse(file_io)

        yield doc if block_given?

        doc.to_s
      end
    end
  end
end

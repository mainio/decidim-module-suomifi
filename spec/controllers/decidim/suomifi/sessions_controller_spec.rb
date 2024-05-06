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
          let!(:suomifi_session) { create(:suomifi_session, user: confirmed_user) }

          it "signs out the user through the Suomi.fi SLO" do
            # Generate a dummy session by requesting the home page.
            get "/"
            request.session["decidim-suomifi.signed_in"] = true
            request.session["saml_uid"] = suomifi_session.saml_uid
            request.session["saml_session_index"] = suomifi_session.saml_session_index

            post "/users/sign_out", env: {
              "rack.session" => request.session,
              "rack.session.options" => request.session.options
            }

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
          # Generate a dummy session by requesting the home page.
          get "/"
          request.session["saml_transaction_id"] = "_274a0148-44ad-4238-bdb0-e56c971ae3bc"
          request.session["saml_uid"] = "AAdzZWNyZXQxfxVUqsT8k/OSMQF/s80N/8TyMb5MERaTUMrYtjpqQV/yStP+CEUegeoHqAVnB9LLOEz2XkE5ZS09VT/4FoAVyonc1z8p5TYIAQI1Hi4wAzINh7OTA6szITMUwP5GfFkW7lGQ0avmRSsr3LODiNGC1zDguiSTX0DtQ9Uq5kQ5nYLz+rJO"

          get "/users/auth/suomifi/slo", params: { SAMLRequest: saml_request }, env: {
            "rack.session" => request.session,
            "rack.session.options" => request.session.options
          }

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

        it "preserves the flash messages after destroying the session" do
          # Generate a dummy session by requesting the home page.
          get "/"

          # Set some arbitrary session variables to pass to the next request
          request.session["test"] = "this should be removed"
          request.session["warden.user.user.key"] = [[123], "abc"]
          request.session["warden.user.user.session"] = { "last_request_at" => Time.now.to_i }

          # See how the flash value is converted to a session variable:
          # https://github.com/rails/rails/blob/12aabe2ee1d97be7a0ca093290a98e21a10d909c/actionpack/lib/action_dispatch/middleware/flash.rb#L138
          request.session["flash"] = {
            "discard" => [],
            "flashes" => {
              alert: "Alert message"
            }
          }

          post "/users/auth/suomifi/spslo", env: {
            "rack.session" => request.session,
            "rack.session.options" => request.session.options
          }

          # Check that all other session keys were removed along with the logout
          # request before redirecting the user.
          expect(request.session).not_to include(
            "test",
            "warden.user.user.key",
            "warden.user.user.session"
          )
          expect(request.session).to include("flash")
          expect(flash[:alert]).to eq("Alert message")
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
        file_io = File.read(filepath)
        doc = Nokogiri::XML::Document.parse(file_io)

        yield doc if block_given?

        doc.to_s
      end
    end
  end
end

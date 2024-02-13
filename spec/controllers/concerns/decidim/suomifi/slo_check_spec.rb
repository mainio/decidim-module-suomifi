# frozen_string_literal: true

require "spec_helper"

describe "Decidim::Suomifi::SloCheck", type: :controller do
  let!(:organization) { create :organization }
  let!(:user) { nil }

  controller do
    include Decidim::Suomifi::SloCheck

    def show
      render plain: "Hello, World!"
    end
  end

  before do
    request.env["decidim.current_organization"] = organization
    routes.draw { get "show" => "anonymous#show" }
    sign_in user if user
  end

  shared_examples "normal request" do
    it "does not redirect or display flash message" do
      get :show

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("Hello, World!")
    end
  end

  context "when there is no user" do
    it_behaves_like "normal request"
  end

  context "when there is a user" do
    let!(:user) { create :user, :confirmed, organization: organization }

    context "without Suomi.fi session" do
      it_behaves_like "normal request"
    end

    context "with Suomi.fi session" do
      let!(:suomifi_session) { create(:suomifi_session, user: user) }

      before do
        get :show
        request.session["decidim-suomifi.signed_in"] = true
        request.session["saml_uid"] = suomifi_session.saml_uid
        request.session["saml_session_index"] = suomifi_session.saml_session_index
      end

      it_behaves_like "normal request"

      context "and the session has ended" do
        let!(:suomifi_session) { create(:suomifi_session, user: user, ended_at: Time.current) }

        it "redirects to the root path and shows a flash warning" do
          get :show

          expect(response).to have_http_status(:found)
          expect(response).to redirect_to("/")
          expect(flash[:warning]).not_to be_empty
        end
      end
    end
  end
end

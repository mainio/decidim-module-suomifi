# frozen_string_literal: true

require "spec_helper"

module Decidim
  module Suomifi
    module Verification
      describe AuthorizationsController, type: :controller do
        routes { Decidim::Suomifi::Verification::Engine.routes }

        let(:user) { create(:user, :confirmed) }

        before do
          request.env["decidim.current_organization"] = user.organization
          sign_in user, scope: :user
        end

        describe "GET new" do
          it "redirects the user" do
            get :new
            expect(response).to redirect_to("/users/auth/suomifi")
          end
        end
      end
    end
  end
end

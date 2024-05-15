# frozen_string_literal: true

require "spec_helper"

describe Decidim::Authorization do
  describe ".create_or_update_from" do
    subject { described_class.create_or_update_from(handler) }

    let(:user) { create(:user) }
    let(:handler_class) do
      Class.new(Decidim::AuthorizationHandler) do
        def authorization_attributes
          # NOTE:
          # After https://github.com/decidim/decidim/pull/10320 is merged,
          # this can be changed into:
          # super.merge(pseudonymized_pin: "abcdef0123456789")
          {
            unique_id:,
            metadata:,
            pseudonymized_pin: "abcdef0123456789"
          }
        end

        def handler_name
          "test_document_auth"
        end
      end
    end
    let(:handler) { handler_class.from_params(user:) }

    let(:authorization) { Decidim::Authorization.last }

    context "when the handler provides additional arguments for the authorization" do
      it "adds the extra attributes for the created authorization" do
        expect(subject).to be(true)
        expect(authorization.pseudonymized_pin).to eq("abcdef0123456789")
      end
    end

    context "when Decidim core is upgraded" do
      it "PLEASE CHECK THE UPGRADE NOTES" do
        # Search: https://github.com/decidim/decidim/pull/10320
        expect(Gem::Version.new(Decidim.version)).to be < Gem::Version.new("0.29.0")
      end
    end
  end
end

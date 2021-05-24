# frozen_string_literal: true

require "spec_helper"

describe Decidim::Suomifi::ActionAuthorizer do
  subject { described_class.new(authorization, options, component, resource) }

  let(:organization) { create(:organization, available_locales: [:fi, :en]) }
  let(:process) { create(:participatory_process, organization: organization) }
  let(:component) { create(:component, manifest_name: "budgets", participatory_space: process) }
  let(:resource) { nil }

  let(:options) do
    {
      "minimum_age" => minimum_age.to_s,
      "allowed_municipalities" => allowed_municipalities,
      "other_authorization_handlers" => other_authorization_handlers
    }
  end
  let(:minimum_age) { 13 }
  let(:allowed_municipalities) { "91,837,49" }
  let(:other_authorization_handlers) { "tampere_documents_authorization_handler" }

  let(:authorization) { create(:authorization, :granted, user: user, metadata: metadata) }
  let(:user) { create :user, organization: organization }
  let(:metadata) do
    {
      municipality: municipality,
      date_of_birth: date_of_birth
    }
  end
  let(:municipality) { "837" }
  let(:date_of_birth) { rand(18..99).years.ago.strftime("%Y-%m-%d") }
  let(:pin_digest) do
    Digest::MD5.hexdigest(
      "FI:150785-5843:#{Rails.application.secrets.secret_key_base}"
    )
  end

  context "when everything is OK" do
    it "returns status_code and data" do
      expect(subject.authorize).to eq([:ok, {}])
    end
  end

  context "when the user is from a wrong municipality" do
    let(:municipality) { "853" }

    it "is unauthorized" do
      expect(subject.authorize).to eq(
        [
          :unauthorized,
          {
            extra_explanation: {
              key: "disallowed_municipality",
              params: { scope: "suomifi_action_authorizer.restrictions" }
            }
          }
        ]
      )
    end
  end

  context "when the user is too young" do
    let(:date_of_birth) { 1.year.ago.strftime("%Y-%m-%d") }

    it "is unauthorized" do
      expect(subject.authorize).to eq(
        [
          :unauthorized,
          {
            extra_explanation: {
              key: "too_young",
              params: {
                scope: "suomifi_action_authorizer.restrictions",
                minimum_age: minimum_age
              }
            }
          }
        ]
      )
    end

    context "when reauthorization is allowed" do
      before do
        # rubocop:disable RSpec/SubjectStub
        allow(subject).to receive(:allow_reauthorization?).and_return(true)
        # rubocop:enable RSpec/SubjectStub
      end

      it "is unauthorized" do
        expect(subject.authorize).to eq(
          [
            :incomplete,
            {
              extra_explanation: {
                key: "too_young",
                params: {
                  scope: "suomifi_action_authorizer.restrictions",
                  minimum_age: minimum_age
                }
              }
            },
            { action: :reauthorize },
            { cancel: true }
          ]
        )
      end
    end
  end

  context "when the user has already voted" do
    let!(:authorization) { create(:authorization, name: "tampere_documents_authorization_handler", metadata: authorization_metadata) }
    let(:authorization_metadata) { { "pin_digest" => pin_digest } }

    it "is unauthorized" do
      expect(subject.authorize).to eq(
        [
          :unauthorized,
          {
            extra_explanation: {
              key: "physically_identified",
              params: {
                scope: "suomifi_action_authorizer.restrictions"
              }
            }
          }
        ]
      )
    end
  end

  describe "#redirect_params" do
    it "returns redirect params" do
      expect(subject.redirect_params).to eq(
        {
          "minimum_age" => minimum_age,
          "allowed_municipalities" => allowed_municipalities
        }
      )
    end
  end
end

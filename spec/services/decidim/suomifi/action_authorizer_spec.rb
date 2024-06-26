# frozen_string_literal: true

require "spec_helper"

describe Decidim::Suomifi::ActionAuthorizer do
  subject { described_class.new(authorization, options, component, resource) }

  let(:organization) { create(:organization) }
  let(:process) { create(:participatory_process, organization:) }
  let(:component) { create(:component, manifest_name: "budgets", participatory_space: process) }
  let(:resource) { nil }

  let(:options) do
    {
      "minimum_age" => minimum_age.to_s,
      "allowed_municipalities" => allowed_municipalities
    }
  end
  let(:minimum_age) { 13 }
  let(:allowed_municipalities) { "91,837,49" }

  let(:authorization) { create(:authorization, :granted, user:, metadata:, pseudonymized_pin: pin_digest) }
  let(:user) { create(:user, organization:) }
  let(:metadata) do
    {
      municipality:,
      date_of_birth:,
      pin_digest:
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
                minimum_age:
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
                  minimum_age:
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
    let!(:document_authorization) do
      create(
        :authorization,
        name: "id_documents",
        metadata: authorization_metadata,
        pseudonymized_pin: pin_digest
      )
    end
    let(:authorization_metadata) { { "pin_digest" => pin_digest } }

    before do
      allow(Decidim::Suomifi).to receive(:other_authorization_handlers).and_return(["id_documents"])
    end

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

    context "when the pin_digest is not defined only in the pseudonymized_pin column" do
      let(:authorization_metadata) { {} }

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

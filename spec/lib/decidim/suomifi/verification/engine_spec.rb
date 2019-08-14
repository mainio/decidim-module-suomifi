# frozen_string_literal: true

require "spec_helper"

describe Decidim::Suomifi::Verification::Engine do
  it "adds the correct routes" do
    expect(described_class.routes.recognize_path("/authorizations/new")).to eq(
      controller: "decidim/suomifi/verification/authorizations",
      action: "new"
    )
    expect(described_class.routes.recognize_path("/")).to eq(
      controller: "decidim/suomifi/verification/authorizations",
      action: "new"
    )
  end

  it "registers the verification workflow" do
    expiration = double
    expect(Decidim::Suomifi.config).to receive(
      :authorization_expiration
    ).and_return(expiration)
    expect(Decidim::Verifications).to receive(
      :register_workflow
    ).with(:suomifi_eid) do |&block|
      workflow = double
      expect(workflow).to receive(:engine=).with(described_class)
      expect(workflow).to receive(:expires_in=).with(expiration)

      block.call(workflow)
    end

    run_initializer("decidim_suomifi.verification_workflow")
    # Decidim::Verifications.register_workflow(:suomifi_eid) do |workflow|
  end

  describe "#load_seed" do
    before { create(:organization) }

    it "adds :suomifi_eid to the organization's available authorizations" do
      described_class.load_seed

      org = Decidim::Organization.first
      expect(org.available_authorizations).to include("suomifi_eid")
    end
  end

  def run_initializer(initializer_name)
    config = described_class.initializers.find do |i|
      i.name == initializer_name
    end
    config.run
  end
end

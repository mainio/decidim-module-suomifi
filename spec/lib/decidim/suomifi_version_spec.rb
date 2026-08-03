# frozen_string_literal: true

require "spec_helper"

describe Decidim::Suomifi do
  describe "::VERSION" do
    subject { described_class::VERSION }

    it { is_expected.to eq("0.31.0") }
  end

  describe "::DECIDIM_VERSION" do
    subject { described_class::DECIDIM_VERSION }

    it { is_expected.to eq("~> 0.31.0") }

    it "is satisfied by the installed Decidim version" do
      expect(Gem::Requirement.new(subject)).to be_satisfied_by(
        Gem::Version.new(Decidim.version)
      )
    end
  end
end

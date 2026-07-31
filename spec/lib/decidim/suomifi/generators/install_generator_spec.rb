# frozen_string_literal: true

require "spec_helper"
require "rails/generators"
require "generators/decidim/suomifi/install_generator"

describe Decidim::Suomifi::Generators::InstallGenerator do
  let(:options) { {} }

  before { subject.options = options }

  describe "#copy_initializer" do
    it "copies the initializer file" do
      # We don't want the generator to actually copy the file
      # rubocop:disable RSpec/SubjectStub
      expect(subject).to receive(:copy_file).with(
        "suomifi_initializer.rb",
        "config/initializers/suomifi.rb"
      )
      # rubocop:enable RSpec/SubjectStub
      subject.copy_initializer
    end

    context "with the test_initializer option set to true" do
      let(:options) { { test_initializer: true } }

      it "copies the test initializer file" do
        # We don't want the generator to actually copy the file
        # rubocop:disable RSpec/SubjectStub
        expect(subject).to receive(:copy_file).with(
          "suomifi_initializer_test.rb",
          "config/initializers/suomifi.rb"
        )
        # rubocop:enable RSpec/SubjectStub
        subject.copy_initializer
      end
    end
  end

  describe "#copy_dummy_certificate" do
    it "does not copy the dummy certificate by default" do
      # We need these expectations to make sure it doesn't do anything
      # rubocop:disable RSpec/SubjectStub
      expect(subject).not_to receive(:empty_directory)
      expect(subject).not_to receive(:copy_file)
      # rubocop:enable RSpec/SubjectStub

      subject.copy_dummy_certificate
    end

    context "with the dummy_cert option set to true" do
      let(:options) { { dummy_cert: true } }

      it "copies the test initializer file" do
        # We don't want the generator to actually copy the file
        # rubocop:disable RSpec/SubjectStub
        expect(subject).to receive(:empty_directory).with("config/cert")
        expect(subject).to receive(:copy_file).with(
          "suomifi_localhost.crt",
          "config/cert/suomifi.crt"
        )
        expect(subject).to receive(:copy_file).with(
          "suomifi_localhost.key",
          "config/cert/suomifi.key"
        )
        # rubocop:enable RSpec/SubjectStub

        subject.copy_dummy_certificate
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

describe Decidim::Suomifi do
  let(:config) { double }

  before do
    allow(subject).to receive(:config).and_return(config)
  end

  describe ".mode" do
    it "returns :production by default" do
      allow(config).to receive(:mode).and_return(nil)
      allow(Rails.application.secrets).to receive(:omniauth).and_return({})

      expect(subject.mode).to eq(:production)
    end

    context "when configured through module configuration" do
      let(:mode) { double }

      it "returns what is set by the module configuration" do
        allow(config).to receive(:mode).and_return(mode)

        expect(subject.mode).to eq(mode)
      end
    end

    context "when configured through OmniAuth configurations" do
      it "returns what is set by the module configuration" do
        allow(config).to receive(:mode).and_return(nil)
        allow(Rails.application.secrets).to receive(:omniauth).and_return(
          suomifi: { mode: "test" }
        )

        expect(subject.mode).to eq(:test)
      end
    end
  end

  describe ".sp_entity_id" do
    it "returns the correct path by default" do
      allow(config).to receive(:sp_entity_id).and_return(nil)
      expect(subject).to receive(:application_host).and_return(
        "https://www.example.org"
      )

      expect(subject.sp_entity_id).to eq(
        "https://www.example.org/users/auth/suomifi/metadata"
      )
    end

    context "when configured through module configuration" do
      let(:sp_entity_id) { double }

      it "returns what is set by the module configuration" do
        allow(config).to receive(:sp_entity_id).and_return(sp_entity_id)

        expect(subject.sp_entity_id).to eq(sp_entity_id)
      end
    end
  end

  describe ".certificate" do
    it "returns the certificate file content when configured with a file" do
      file = double
      contents = double
      allow(subject).to receive(:certificate_file).and_return(file)
      allow(File).to receive(:read).with(file).and_return(contents)

      expect(subject.certificate).to eq(contents)
    end

    context "when configured through module configuration" do
      let(:certificate) { double }

      it "returns what is set by the module configuration" do
        allow(subject).to receive(:certificate_file).and_return(nil)
        allow(config).to receive(:certificate).and_return(certificate)

        expect(subject.certificate).to eq(certificate)
      end
    end
  end

  describe ".private_key" do
    it "returns the private key file content when configured with a file" do
      file = double
      contents = double
      allow(subject).to receive(:private_key_file).and_return(file)
      allow(File).to receive(:read).with(file).and_return(contents)

      expect(subject.private_key).to eq(contents)
    end

    context "when configured through module configuration" do
      let(:private_key) { double }

      it "returns what is set by the module configuration" do
        allow(subject).to receive(:private_key_file).and_return(nil)
        allow(config).to receive(:private_key).and_return(private_key)

        expect(subject.private_key).to eq(private_key)
      end
    end
  end

  describe ".omniauth_settings" do
    let(:mode) { double }
    let(:scope_of_data) { double }
    let(:sp_entity_id) { double }
    let(:certificate) { double }
    let(:private_key) { double }
    let(:idp_slo_session_destroy) { double }
    let(:extra) { { extra1: "abc", extra2: 123 } }

    it "returns the expected omniauth configuration hash" do
      allow(subject).to receive(:mode).and_return(mode)
      allow(subject).to receive(:scope_of_data).and_return(scope_of_data)
      allow(subject).to receive(:sp_entity_id).and_return(sp_entity_id)
      allow(subject).to receive(:certificate).and_return(certificate)
      allow(subject).to receive(:private_key).and_return(private_key)
      allow(subject).to receive(:idp_slo_session_destroy).and_return(idp_slo_session_destroy)
      allow(config).to receive(:extra).and_return(extra)

      expect(subject.omniauth_settings).to include(
        mode: mode,
        scope_of_data: scope_of_data,
        sp_entity_id: sp_entity_id,
        certificate: certificate,
        private_key: private_key,
        idp_slo_session_destroy: idp_slo_session_destroy,
        extra1: "abc",
        extra2: 123
      )
    end
  end

  describe ".application_host" do
    let(:rails_config) { double }
    let(:controller_config) { double }
    let(:mailer_config) { double }

    let(:controller_defaults) { nil }
    let(:mailer_defaults) { nil }

    before do
      allow(Rails.application).to receive(:config).and_return(rails_config)
      allow(rails_config).to receive(:action_controller).and_return(controller_config)
      allow(rails_config).to receive(:action_mailer).and_return(mailer_config)
      allow(controller_config).to receive(:default_url_options).and_return(controller_defaults)
      allow(mailer_config).to receive(:default_url_options).and_return(mailer_defaults)
    end

    it "returns the development host by default" do
      expect(subject.application_host).to eq("http://localhost:3000")
    end

    context "with controller config without a host" do
      let(:controller_defaults) { { port: 8000 } }

      it "returns the default development host without applying the configured port" do
        expect(subject.application_host).to eq("http://localhost:3000")
      end

      context "and mailer configuration having a host" do
        let(:mailer_defaults) { { host: "www.example.org" } }

        it "returns the mailer config host" do
          expect(subject.application_host).to eq("https://www.example.org")
        end
      end

      context "and mailer configuration having a host and a port" do
        let(:mailer_defaults) { { host: "www.example.org", port: 4443 } }

        it "returns the mailer config host and port" do
          expect(subject.application_host).to eq("https://www.example.org:4443")
        end
      end
    end

    context "with controller config having a host" do
      let(:controller_defaults) { { host: "www.example.org" } }
      let(:mailer_defaults) { { host: "www.mailer.org", port: 4443 } }

      it "returns the controller config host" do
        expect(subject.application_host).to eq("https://www.example.org")
      end
    end

    context "with controller config having a host and a port" do
      let(:controller_defaults) { { host: "www.example.org", port: 8080 } }
      let(:mailer_defaults) { { host: "www.mailer.org", port: 4443 } }

      it "returns the controller config host and port" do
        expect(subject.application_host).to eq("https://www.example.org:8080")
      end

      context "when the port is 80" do
        let(:controller_defaults) { { host: "www.example.org", port: 80 } }

        it "does not append it to the host" do
          expect(subject.application_host).to eq("http://www.example.org")
        end
      end

      context "when the port is 443" do
        let(:controller_defaults) { { host: "www.example.org", port: 443 } }

        it "does not append it to the host" do
          expect(subject.application_host).to eq("https://www.example.org")
        end
      end
    end

    context "with mailer config having a host" do
      let(:mailer_defaults) { { host: "www.example.org" } }

      it "returns the mailer config host" do
        expect(subject.application_host).to eq("https://www.example.org")
      end
    end

    context "with mailer config having a host and a port" do
      let(:mailer_defaults) { { host: "www.example.org", port: 8080 } }

      it "returns the mailer config host and port" do
        expect(subject.application_host).to eq("https://www.example.org:8080")
      end

      context "when the port is 80" do
        let(:mailer_defaults) { { host: "www.example.org", port: 80 } }

        it "does not append it to the host" do
          expect(subject.application_host).to eq("http://www.example.org")
        end
      end

      context "when the port is 443" do
        let(:mailer_defaults) { { host: "www.example.org", port: 443 } }

        it "does not append it to the host" do
          expect(subject.application_host).to eq("https://www.example.org")
        end
      end
    end
  end
end

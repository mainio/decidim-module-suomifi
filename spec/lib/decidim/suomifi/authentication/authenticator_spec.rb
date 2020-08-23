# frozen_string_literal: true

require "spec_helper"

describe Decidim::Suomifi::Authentication::Authenticator do
  subject { described_class.new(organization, oauth_hash) }

  let(:organization) { create(:organization) }
  let(:oauth_hash) do
    {
      provider: oauth_provider,
      uid: oauth_uid,
      info: {
        name: oauth_name,
        image: oauth_image
      },
      extra: {
        saml_attributes: saml_attributes
      }
    }
  end
  let(:oauth_provider) { "provider" }
  let(:oauth_uid) { "uid" }
  let(:oauth_name) { "Marja Mainio" }
  let(:oauth_image) { nil }
  let(:saml_attributes) do
    {
      national_identification_number: "150785-5843",
      common_name: "Mainio Marja Mirja",
      display_name: "Marja Mainio",
      first_names: "Marja Mirja",
      given_name: "Marja",
      last_name: "Mainio"
    }
  end

  describe "#verified_email" do
    context "when email is available in the SAML attributes" do
      let(:saml_attributes) { { email: "user@example.org" } }

      it "returns the email from SAML attributes" do
        expect(subject.verified_email).to eq("user@example.org")
      end

      context "and Suomi.fi emails are disabled" do
        let(:saml_attributes) { { email: "user@example.org", national_identification_number: "150785-5843" } }

        before do
          allow(Decidim::Suomifi).to receive(:use_suomifi_email).and_return(false)
        end

        it "auto-creates the email using the known pattern" do
          expect(subject.verified_email).to match(/suomifi-[a-z0-9]{32}@1.lvh.me/)
        end
      end
    end

    context "when email is not available in the SAML attributes" do
      let(:saml_attributes) { { national_identification_number: "150785-5843" } }

      it "auto-creates the email using the known pattern" do
        expect(subject.verified_email).to match(/suomifi-[a-z0-9]{32}@1.lvh.me/)
      end

      context "and auto_email_domain is not defined" do
        before do
          allow(Decidim::Suomifi).to receive(:auto_email_domain).and_return(nil)
        end

        it "auto-creates the email using the known pattern" do
          expect(subject.verified_email).to match(/suomifi-[a-z0-9]{32}@#{organization.host}/)
        end
      end
    end
  end

  describe "#user_params_from_oauth_hash" do
    it "returns the expected hash" do
      signature = ::Decidim::OmniauthRegistrationForm.create_signature(
        oauth_provider,
        oauth_uid
      )

      expect(subject.user_params_from_oauth_hash).to include(
        provider: oauth_provider,
        uid: oauth_uid,
        name: "Marja Mainio",
        nickname: "Marja Mainio",
        oauth_signature: signature,
        avatar_url: nil,
        raw_data: oauth_hash
      )
    end

    context "when oauth data is empty" do
      let(:oauth_hash) { {} }

      it "returns nil" do
        expect(subject.user_params_from_oauth_hash).to be_nil
      end
    end

    context "when SAML attributes are empty" do
      let(:saml_attributes) { {} }

      it "returns nil" do
        expect(subject.user_params_from_oauth_hash).to be_nil
      end
    end

    context "when user identifier is blank" do
      let(:oauth_uid) { nil }

      it "returns nil" do
        expect(subject.user_params_from_oauth_hash).to be_nil
      end
    end

    context "when given name does not exist" do
      let(:oauth_name) { nil }
      let(:saml_attributes) do
        {
          first_names: "Mikko Mika",
          last_name: "Mallikas"
        }
      end

      it "uses both first names as the first name" do
        expect(subject.user_params_from_oauth_hash).to include(
          name: "Mikko Mika Mallikas",
          nickname: "Mikko Mika Mallikas"
        )
      end
    end

    context "when given name and first names do not exist" do
      let(:oauth_name) { nil }
      let(:saml_attributes) do
        {
          eidas_first_names: "Mikko Mika",
          last_name: "Mallikas"
        }
      end

      it "uses both eidas first names as the first name" do
        expect(subject.user_params_from_oauth_hash).to include(
          name: "Mikko Mika Mallikas",
          nickname: "Mikko Mika Mallikas"
        )
      end
    end

    context "when last name does not exist" do
      let(:oauth_name) { nil }
      let(:saml_attributes) do
        {
          given_name: "Mikko",
          eidas_family_name: "Mallikas"
        }
      end

      it "uses eidas last names as the last name" do
        expect(subject.user_params_from_oauth_hash).to include(
          name: "Mikko Mallikas",
          nickname: "Mikko Mallikas"
        )
      end
    end
  end

  describe "#validate!" do
    it "returns true for valid authentication data" do
      expect(subject.validate!).to be(true)
    end

    context "when no SAML attributes are available" do
      let(:saml_attributes) { {} }

      it "raises a ValidationError" do
        expect do
          subject.validate!
        end.to raise_error(
          Decidim::Suomifi::Authentication::ValidationError,
          "No SAML data provided"
        )
      end
    end

    context "when all SAML attributes values are blank" do
      let(:saml_attributes) do
        {
          national_identification_number: nil,
          common_name: nil,
          display_name: nil,
          first_names: nil,
          given_name: nil,
          last_name: nil
        }
      end

      it "raises a ValidationError" do
        expect do
          subject.validate!
        end.to raise_error(
          Decidim::Suomifi::Authentication::ValidationError,
          "Invalid SAML data"
        )
      end
    end

    context "when there is no person identifier" do
      let(:saml_attributes) do
        {
          common_name: "Mainio Marja Mirja",
          display_name: "Marja Mainio",
          first_names: "Marja Mirja",
          given_name: "Marja",
          last_name: "Mainio"
        }
      end

      it "raises a ValidationError" do
        expect do
          subject.validate!
        end.to raise_error(
          Decidim::Suomifi::Authentication::ValidationError,
          "Invalid person dentifier"
        )
      end
    end
  end

  describe "#identify_user!" do
    let(:user) { create(:user, :confirmed, organization: organization) }

    it "creates a new identity for the user" do
      id = subject.identify_user!(user)

      expect(Decidim::Identity.count).to eq(1)
      expect(Decidim::Identity.last.id).to eq(id.id)
      expect(id.organization.id).to eq(organization.id)
      expect(id.user.id).to eq(user.id)
      expect(id.provider).to eq(oauth_provider)
      expect(id.uid).to eq(oauth_uid)
    end

    context "when an identity already exists" do
      let!(:identity) do
        user.identities.create!(
          organization: organization,
          provider: oauth_provider,
          uid: oauth_uid
        )
      end

      it "returns the same identity" do
        expect(subject.identify_user!(user).id).to eq(identity.id)
      end
    end

    context "when a matching identity already exists for another user" do
      let(:another_user) { create(:user, :confirmed, organization: organization) }

      before do
        another_user.identities.create!(
          organization: organization,
          provider: oauth_provider,
          uid: oauth_uid
        )
      end

      it "raises an IdentityBoundToOtherUserError" do
        expect do
          subject.identify_user!(user)
        end.to raise_error(
          Decidim::Suomifi::Authentication::IdentityBoundToOtherUserError
        )
      end
    end
  end

  describe "#authorize_user!" do
    let(:user) { create(:user, :confirmed, organization: organization) }
    let(:signature) do
      ::Decidim::OmniauthRegistrationForm.create_signature(
        oauth_provider,
        oauth_uid
      )
    end
    let(:pin_digest) do
      Digest::MD5.hexdigest(
        "FI:150785-5843:#{Rails.application.secrets.secret_key_base}"
      )
    end

    it "creates a new authorization for the user" do
      auth = subject.authorize_user!(user)

      expect(Decidim::Authorization.count).to eq(1)
      expect(Decidim::Authorization.last.id).to eq(auth.id)
      expect(auth.user.id).to eq(user.id)
      expect(auth.unique_id).to eq(signature)
      expect(auth.metadata).to include(
        "eidas" => false,
        "pin_digest" => pin_digest,
        "gender" => "f",
        "date_of_birth" => "1985-07-15",
        "first_name" => "Marja Mirja",
        "given_name" => "Marja",
        "last_name" => "Mainio",
        "municipality" => nil,
        "municipality_name" => nil,
        "postal_code" => nil,
        "permanent_address" => false
      )
    end

    context "when an authorization already exists" do
      let!(:authorization) do
        Decidim::Authorization.create!(
          name: "suomifi_eid",
          user: user,
          unique_id: signature
        )
      end

      it "returns the existing authorization and updates it" do
        auth = subject.authorize_user!(user)

        expect(auth.id).to eq(authorization.id)
        expect(auth.metadata).to include(
          "eidas" => false,
          "pin_digest" => pin_digest,
          "gender" => "f",
          "date_of_birth" => "1985-07-15",
          "first_name" => "Marja Mirja",
          "given_name" => "Marja",
          "last_name" => "Mainio",
          "municipality" => nil,
          "municipality_name" => nil,
          "postal_code" => nil,
          "permanent_address" => false
        )
      end
    end

    context "when a matching authorization already exists for another user" do
      let(:another_user) { create(:user, :confirmed, organization: organization) }

      before do
        Decidim::Authorization.create!(
          name: "suomifi_eid",
          user: another_user,
          unique_id: signature
        )
      end

      it "raises an IdentityBoundToOtherUserError" do
        expect do
          subject.authorize_user!(user)
        end.to raise_error(
          Decidim::Suomifi::Authentication::AuthorizationBoundToOtherUserError
        )
      end
    end
  end
end

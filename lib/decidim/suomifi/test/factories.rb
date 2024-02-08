# frozen_string_literal: true

FactoryBot.define do
  sequence(:suomifi_session_uid) { |n| "uid#{n}" }
  sequence(:suomifi_session_index) { |n| "uid#{n}" }

  factory :suomifi_session, class: "Decidim::Suomifi::Session" do
    user
    saml_uid { generate(:suomifi_session_uid) }
    saml_session_index { generate(:suomifi_session_index) }
  end
end

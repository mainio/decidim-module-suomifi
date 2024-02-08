# frozen_string_literal: true

module Decidim
  module Suomifi
    class Session < Suomifi::ApplicationRecord
      belongs_to :user, -> { try(:entire_collection) || self }, foreign_key: "decidim_user_id", class_name: "Decidim::User"

      validates :saml_uid, presence: true, uniqueness: true
      validates :saml_session_index, presence: true

      def ended?
        ended_at.present?
      end
    end
  end
end

# frozen_string_literal: true

module Decidim
  module Suomifi
    module AuthorizationExtensions
      extend ActiveSupport::Concern

      included do
        # Needed to be able to provide additional attributes to the
        # authorization through the handler. Later this will hopefully become
        # a core feature.
        #
        # See: https://github.com/decidim/decidim/pull/10320
        def self.create_or_update_from(handler)
          authorization = find_or_initialize_by(
            user: handler.user,
            name: handler.handler_name
          )

          # Overridden functionality
          authorization.attributes = handler.try(:authorization_attributes) || {
            unique_id: handler.unique_id,
            metadata: handler.metadata
          }

          authorization.grant!
        end
      end
    end
  end
end

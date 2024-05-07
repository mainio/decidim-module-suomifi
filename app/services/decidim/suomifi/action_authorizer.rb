# frozen_string_literal: true

module Decidim
  module Suomifi
    class ActionAuthorizer < Decidim::Verifications::DefaultActionAuthorizer
      # Overrides the parent class method, but it still uses it to keep the base
      # behavior
      def authorize
        requirements!

        status_code, data = *super

        return [status_code, data] unless status_code == :ok

        if voted_physically?
          status_code = :unauthorized
          data[:extra_explanation] = {
            key: "physically_identified",
            params: {
              scope: "suomifi_action_authorizer.restrictions"
            }
          }
        elsif !authorized_municipality_allowed?
          status_code = :unauthorized
          data[:extra_explanation] = {
            key: "disallowed_municipality",
            params: {
              scope: "suomifi_action_authorizer.restrictions"
            }
          }
        elsif !authorized_age_allowed?
          status_code = :unauthorized
          data[:extra_explanation] = {
            key: "too_young",
            params: {
              scope: "suomifi_action_authorizer.restrictions",
              minimum_age:
            }
          }
        end

        # In case reauthorization is allowed (i.e. no votes have been casted),
        # show the reauthorization modal that takes the user back to the "new"
        # action in the authorization handler.
        if status_code == :unauthorized && allow_reauthorization?
          return [
            :incomplete,
            { extra_explanation: data[:extra_explanation] },
            { action: :reauthorize },
            { cancel: true }
          ]
        end

        [status_code, data]
      end

      # Adds the requirements to the redirect URL, to allow forms to inform about
      # them
      def redirect_params
        {
          "minimum_age" => minimum_age,
          "allowed_municipalities" => allowed_municipalities.join(",")
        }
      end

      private

      # This will initially delete the requirements from the authorization options
      # so that they are not directly checked against the user's metadata.
      def requirements!
        allowed_municipalities
        minimum_age
      end

      def voted_physically?
        return false if other_authorization_handlers.blank?

        other_authorization_handlers.each do |authorization_handler|
          return true if Decidim::Authorization.where(
            name: authorization_handler,
            pseudonymized_pin: authorization.pseudonymized_pin
          ).any?
        end
        false
      end

      def authorized_municipality_allowed?
        return true if allowed_municipalities.blank?
        return false if authorization.metadata["municipality"].blank?

        allowed_municipalities.include?(authorization.metadata["municipality"])
      end

      def authorized_age_allowed?
        authorization_age >= minimum_age
      end

      def authorization_age
        return nil if authorization.metadata["date_of_birth"].blank?

        @authorization_age ||= begin
          now = Time.now.utc.to_date
          bd = Date.strptime(authorization.metadata["date_of_birth"], "%Y-%m-%d")
          now.year - bd.year - (bd.to_date.change(year: now.year) > now ? 1 : 0)
        end
      end

      def minimum_age
        @minimum_age ||= options.delete("minimum_age").to_i || 0
      end

      def allowed_municipalities
        @allowed_municipalities ||= options.delete("allowed_municipalities").to_s.split(",").compact.collect(&:to_s)
      end

      def allow_reauthorization?
        false
      end

      def other_authorization_handlers
        Array Decidim::Suomifi.other_authorization_handlers
      end
    end
  end
end

# frozen_string_literal: true

namespace :decidim do
  namespace :suomifi do
    desc "Copy pin digest from metadata to its own column"
    task copy_pin_digests: :environment do
      Decidim::Authorization.all.each do |authorization|
        next if authorization.name != "suomifi_eid" || authorization.pseudonymized_pin.present?

        authorization.update(
          pseudonymized_pin: authorization.metadata["pin_digest"]
        )
      end
    end
  end
end

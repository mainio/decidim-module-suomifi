# frozen_string_literal: true

require "rails/generators/base"

module Decidim
  module Suomifi
    module Generators
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("../../templates", __dir__)

        desc "Creates a Decidim Suomi.fi initializer and copies locale files to your application."

        class_option(
          :dummy_cert,
          desc: "Defines whether to create a dummy certificate for localhost.",
          type: :boolean,
          default: false
        )

        class_option(
          :test_initializer,
          desc: "Copies the test initializer instead of the actual one (for test dummy app).",
          type: :boolean,
          default: false,
          hide: true
        )

        def copy_initializer
          if options[:test_initializer]
            copy_file "suomifi_initializer_test.rb", "config/initializers/suomifi.rb"
          else
            copy_file "suomifi_initializer.rb", "config/initializers/suomifi.rb"
          end
        end

        def copy_dummy_certificate
          if options[:dummy_cert]
            empty_directory "config/cert"
            copy_file "suomifi_localhost.crt", "config/cert/suomifi.crt"
            copy_file "suomifi_localhost.key", "config/cert/suomifi.key"
          end
        end
      end
    end
  end
end

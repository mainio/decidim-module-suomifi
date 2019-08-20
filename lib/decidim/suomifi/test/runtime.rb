# frozen_string_literal: true

module Decidim
  module Suomifi
    module Test
      class Runtime
        # Ability to stub the requests already in the control class
        include WebMock::API

        def self.initializer(&block)
          @block = block
        end

        def self.initialize
          new.instance_initialize(&@block)
        end

        def self.load_app
          engine_spec_dir = File.join(Dir.pwd, "spec")

          require "#{Decidim::Dev.dummy_app_path}/config/environment"

          Dir["#{engine_spec_dir}/shared/**/*.rb"].each { |f| require f }

          require "paper_trail/frameworks/rspec"

          require "decidim/dev/test/spec_helper"
        end

        def self.cert_store
          @cert_store ||= CertStore.new
        end

        def instance_initialize
          yield self

          # Setup the Suomi.fi OmniAuth strategy for Devise
          # ::Devise.setup do |config|
          #   config.omniauth(
          #     :suomifi,
          #     Decidim::Suomifi.omniauth_settings
          #   )
          # end
        end
      end
    end
  end
end

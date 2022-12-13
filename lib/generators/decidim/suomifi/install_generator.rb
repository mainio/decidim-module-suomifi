# frozen_string_literal: true

require "rails/generators/base"

module Decidim
  module Suomifi
    module Generators
      class InstallGenerator < Rails::Generators::Base
        source_root File.expand_path("../../templates", __dir__)

        desc "Creates a Devise initializer and copy locale files to your application."

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

        def enable_authentication
          secrets_path = Rails.application.root.join("config", "secrets.yml")
          secrets_content = ERB.new(File.read(secrets_path)).result
          secrets = YAML.safe_load(secrets_content, [], [], true)

          if secrets["default"]["omniauth"]["suomifi"]
            say_status :identical, "config/secrets.yml", :blue
          else
            mod = SecretsModifier.new(secrets_path)
            final = mod.modify

            target_path = Rails.application.root.join("config", "secrets.yml")
            File.open(target_path, "w") { |f| f.puts final }

            say_status :insert, "config/secrets.yml", :green
          end
        end

        class SecretsModifier
          def initialize(filepath)
            @filepath = filepath
          end

          def modify
            self.inside_config = false
            self.inside_omniauth = false
            self.config_branch = nil
            @final = ""

            @empty_line_count = 0
            File.readlines(filepath).each do |line|
              if line =~ /^$/
                @empty_line_count += 1
                next
              else
                handle_line line
                insert_empty_lines
              end

              @final += line
            end
            insert_empty_lines

            @final
          end

          private

          attr_accessor :filepath, :empty_line_count, :inside_config, :inside_omniauth, :config_branch

          def handle_line(line)
            if inside_config && line =~ /^  omniauth:/
              self.inside_omniauth = true
            elsif inside_omniauth && (line =~ /^(  )?[a-z]+/ || line =~ /^#.*/)
              inject_suomifi_config
              self.inside_omniauth = false
            end

            return unless line =~ /^[a-z]+/

            # A new root configuration block starts
            self.inside_config = false
            self.inside_omniauth = false

            if line =~ /^default:/
              self.inside_config = true
              self.config_branch = :default
            elsif line =~ /^development:/
              self.inside_config = true
              self.config_branch = :development
            elsif line =~ /^test:/
              self.inside_config = true
              self.config_branch = :test
            end
          end

          def insert_empty_lines
            @final += "\n" * empty_line_count
            @empty_line_count = 0
          end

          def inject_suomifi_config
            @final += "    suomifi:\n"
            if %i(development test).include?(config_branch)
              @final += "      enabled: true\n"
              @final += "      mode: test\n"
            else
              @final += "      enabled: false\n"
            end
            @final += "      icon: globe\n"
          end
        end
      end
    end
  end
end

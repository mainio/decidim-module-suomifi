# frozen_string_literal: true

source "https://rubygems.org"

ruby RUBY_VERSION

# Inside the development app, the relative require has to be one level up, as
# the Gemfile is copied to the development_app folder (almost) as is.
base_path = ""
base_path = "../" if File.basename(__dir__) == "development_app"
require_relative "#{base_path}lib/decidim/suomifi/version"

DECIDIM_VERSION = Decidim::Suomifi::DECIDIM_VERSION
# DECIDIM_VERSION = { github: "decidim/decidim", branch: "release/0.23-stable" }

gem "decidim", DECIDIM_VERSION
gem "decidim-suomifi", path: "."

gem "omniauth-suomifi", "~> 0.4.1"

gem "bootsnap", "~> 1.4"
gem "puma", "~> 4.3.3"
gem "uglifier", "~> 4.1"

group :development, :test do
  gem "byebug", "~> 11.0", platform: :mri

  gem "decidim-dev", DECIDIM_VERSION
end

group :development do
  gem "faker", "~> 1.9"
  gem "letter_opener_web", "~> 1.4"
  gem "listen", "~> 3.1"
  gem "spring", "~> 2.0"
  gem "spring-watcher-listen", "~> 2.0"
  gem "web-console", "~> 3.7"
end

group :test do
  gem "codecov", require: false
  gem "xmlenc", "~> 0.7.1"
end

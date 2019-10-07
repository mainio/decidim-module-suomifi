# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "decidim/suomifi/version"

Gem::Specification.new do |spec|
  spec.name = "decidim-suomifi"
  spec.version = Decidim::Suomifi::VERSION
  spec.authors = ["Antti Hukkanen"]
  spec.email = ["antti.hukkanen@mainiotech.fi"]

  spec.summary = "Provides possibility to bind Suomi.fi authentication provider to Decidim."
  spec.description = "Adds Suomi.fi authentication provider to Decidim."
  spec.homepage = "https://github.com/mainio/decidim-module-suomifi"
  spec.license = "AGPL-3.0"

  spec.files = Dir[
    "{app,config,lib}/**/*",
    "LICENSE-AGPLv3.txt",
    "Rakefile",
    "README.md"
  ]

  spec.require_paths = ["lib"]

  spec.add_dependency "decidim-core", Decidim::Suomifi::DECIDIM_VERSION
  spec.add_dependency "henkilotunnus", "~> 1.1.0"
  spec.add_dependency "omniauth-suomifi", "~> 0.2.0"

  spec.add_development_dependency "decidim-dev", Decidim::Suomifi::DECIDIM_VERSION

  # Required for encoding the SAML responses
  spec.add_development_dependency "xmlenc", "~> 0.7.1"
end

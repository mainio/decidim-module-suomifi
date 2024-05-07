# frozen_string_literal: true

require "decidim/dev"

ENV["RAILS_ENV"] ||= "test"

require "simplecov" if ENV["SIMPLECOV"]

require "decidim/dev/test/base_spec_helper"

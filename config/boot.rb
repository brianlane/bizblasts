# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.

# Set environment to disable propshaft in test environment
ENV["DISABLE_PROPSHAFT"] = "true" if ENV["RAILS_ENV"] == "test" || ENV["RACK_ENV"] == "test"

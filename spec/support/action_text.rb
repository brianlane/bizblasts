# frozen_string_literal: true

# ActionText configuration for RSpec tests
# This fixes Rails 8 ActionText::Rendering with_renderer compatibility issues

RSpec.configure do |config|
  # Configure ActionText renderer for each test
  config.before(:each) do
    # Set up ActionText renderer to avoid "wrong number of arguments" errors
    if defined?(ActionText)
      # Ensure a renderer is available during tests (Rails auto-sets one, but we guard just in case)
      ActionText::Content.renderer ||= ApplicationController.renderer.new
      
      # NOTE: Do NOT stub `with_renderer`. Stubbing it can change method arity and
      # trigger `ArgumentError: wrong number of arguments` when ActionText invokes
      # the method with parameters. Leaving the original implementation intact
      # avoids this problem while still providing full rendering capability in
      # specs.
    end
  end
  
  # For system tests, include ActionText helpers
  config.include ActionText::SystemTestHelper, type: :system if defined?(ActionText::SystemTestHelper)
end
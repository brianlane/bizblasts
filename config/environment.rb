# frozen_string_literal: true

# Load the Rails application.
require_relative "application"

# Prevent frozen autoload_paths errors by removing the set_autoload_paths initializer
#Rails.application.initializers.delete_if { |init| init.name.to_s == "set_autoload_paths" }

# Initialize the Rails application.
Rails.application.initialize!

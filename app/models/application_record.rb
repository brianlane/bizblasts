# frozen_string_literal: true

# Base model class for all application models
# Implements primary_abstract_class for multi-database support
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end

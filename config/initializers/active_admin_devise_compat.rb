# frozen_string_literal: true

# ActiveAdmin 3.4.x hard-caps Devise < 5 in its dependency check.
# Devise 5 works with our setup, so widen the requirement until upstream updates.
require "active_admin/dependency"

if defined?(ActiveAdmin::Dependency::Requirements::DEVISE)
  ActiveAdmin::Dependency::Requirements.send(:remove_const, :DEVISE)
end

ActiveAdmin::Dependency::Requirements::DEVISE = [">= 4.0", "< 6"].freeze

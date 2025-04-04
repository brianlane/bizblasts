# frozen_string_literal: true

# Concern for multi-tenant models in the application
# Applies acts_as_tenant scoping to all models and ensures tenant isolation
module TenantScoped
  extend ActiveSupport::Concern

  included do
    # Use the ActsAsTenant functionality to scope the model to a tenant
    # This automatically adds a belongs_to association and scoping
    acts_as_tenant(:business)
    
    # Ensure records are always associated with a business
    validates :business, presence: true

    # Add scope for active records, common across many models
    scope :active, -> { where(active: true) }

    # Add default ordering if the model has a position column
    scope :ordered, -> { order(:position) if column_names.include?('position') }
    
    # Add scope for recent records if the model has timestamps
    scope :recent, -> { order(created_at: :desc) if column_names.include?('created_at') }
  end

  class_methods do
    # Method to safely find records even in a multi-tenant context
    # Falls back to normal find if no tenant is set
    def safe_find(id)
      ActsAsTenant.current_tenant ? find_by(id: id) : find(id)
    end
  end
end

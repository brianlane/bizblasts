# frozen_string_literal: true

# Company model that represents a tenant in the multi-tenant architecture
# Manages subdomain validation and normalization for tenant routing
class Company < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :services, dependent: :destroy
  has_many :appointments, dependent: :destroy

  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: { case_sensitive: false },
                        format: { 
                          with: /\A[a-z0-9]+\z/, 
                          message: :lowercase_alphanumeric_only
                        }

  before_validation :normalize_subdomain

  # Used for easy reference in controllers
  def self.current
    ActsAsTenant.current_tenant
  end

  private

  def normalize_subdomain
    # Convert subdomain to lowercase and remove any spaces or special characters
    self.subdomain = subdomain.to_s.downcase.gsub(/[^a-z0-9]/, "") if subdomain
  end
end

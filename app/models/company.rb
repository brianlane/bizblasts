# app/models/company.rb
class Company < ApplicationRecord
    validates :name, presence: true
    validates :subdomain, presence: true, uniqueness: true,
              format: { with: /\A[a-z0-9]+\z/, message: "only allows lowercase letters and numbers without spaces" }

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

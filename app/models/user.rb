# frozen_string_literal: true

# User model that handles authentication and user management
# Uses Devise for authentication and acts_as_tenant for multi-tenancy
class User < ApplicationRecord
  acts_as_tenant(:company)

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Make email unique per tenant rather than globally
  validates :email, uniqueness: { scope: :company_id }
end

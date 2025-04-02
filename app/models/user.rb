# frozen_string_literal: true

# User model that handles authentication and user management
# Uses Devise for authentication and acts_as_tenant for multi-tenancy
class User < ApplicationRecord
  acts_as_tenant(:company)

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Override Devise's default uniqueness validation
  def email_changed?
    false
  end
  
  # Override Devise's email uniqueness validator 
  # to ensure uniqueness is scoped to company_id
  def self.find_by_email(email)
    unscoped.find_by(email: email, company_id: ActsAsTenant.current_tenant&.id)
  end
  
  # Keep original email uniqueness validation from our model
  validates :email, uniqueness: { scope: :company_id }
  
  # Ensure company_id is set before validation
  before_validation :ensure_company_id_set
  
  private
  
  def ensure_company_id_set
    self.company_id ||= ActsAsTenant.current_tenant&.id
  end
end

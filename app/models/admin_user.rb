class AdminUser < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, 
         :recoverable, :rememberable, :validatable

  # Allow searching/filtering on these attributes in ActiveAdmin
  def self.ransackable_attributes(auth_object = nil)
    # List attributes available for filtering in app/admin/admin_users.rb
    # Exclude sensitive attributes like encrypted_password, reset_password_token
    %w[id email current_sign_in_at sign_in_count created_at updated_at remember_created_at]
  end

  # Add ransackable_associations if needed, though likely not for AdminUser
  # def self.ransackable_associations(auth_object = nil)
  #   []
  # end
end

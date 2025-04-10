class ClientBusiness < ApplicationRecord
  belongs_to :user
  belongs_to :business
  
  # Validation to ensure a user is only linked to a business once
  validates :user_id, uniqueness: { scope: :business_id, message: "is already associated with this business" }
end

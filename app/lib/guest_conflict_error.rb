# Custom error for guest checkout conflicts when email/phone belongs to existing user
class GuestConflictError < StandardError
  attr_reader :email, :phone, :business_id, :existing_user_id

  def initialize(message, email: nil, phone: nil, business_id: nil, existing_user_id: nil)
    super(message)
    @email = email
    @phone = phone
    @business_id = business_id
    @existing_user_id = existing_user_id
  end

  def to_h
    {
      message: message,
      email: email,
      phone: phone,
      business_id: business_id,
      existing_user_id: existing_user_id
    }
  end
end
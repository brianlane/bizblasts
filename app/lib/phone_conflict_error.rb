# Custom error for phone number conflicts in customer linking
class PhoneConflictError < StandardError
  attr_reader :phone, :business_id, :existing_user_id, :attempted_user_id

  def initialize(message, phone: nil, business_id: nil, existing_user_id: nil, attempted_user_id: nil)
    super(message)
    @phone = phone
    @business_id = business_id
    @existing_user_id = existing_user_id
    @attempted_user_id = attempted_user_id
  end

  def to_h
    {
      message: message,
      phone: phone,
      business_id: business_id,
      existing_user_id: existing_user_id,
      attempted_user_id: attempted_user_id
    }
  end
end
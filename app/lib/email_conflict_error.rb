# Custom error for email conflicts in customer linking
class EmailConflictError < StandardError
  attr_reader :email, :business_id, :existing_user_id, :attempted_user_id

  def initialize(message, email: nil, business_id: nil, existing_user_id: nil, attempted_user_id: nil)
    super(message)
    @email = email
    @business_id = business_id
    @existing_user_id = existing_user_id
    @attempted_user_id = attempted_user_id
  end

  def to_h
    {
      message: message,
      email: email,
      business_id: business_id,
      existing_user_id: existing_user_id,
      attempted_user_id: attempted_user_id
    }
  end
end

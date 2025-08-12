# frozen_string_literal: true

# Concern for generating globally unique unsubscribe tokens
# Ensures tokens are unique across User and TenantCustomer tables
module UnsubscribeTokenGenerator
  extend ActiveSupport::Concern

  private

  def generate_unsubscribe_token
    loop do
      self.unsubscribe_token = SecureRandom.hex(32)
      # Check for global uniqueness across both User and TenantCustomer tables
      break unless User.exists?(unsubscribe_token: unsubscribe_token) || 
                   TenantCustomer.exists?(unsubscribe_token: unsubscribe_token)
    end
    
    # Save the token if the record is persisted, with error handling
    if persisted?
      unless save(validate: false)
        Rails.logger.error "[TOKEN] Failed to save unsubscribe token for #{self.class.name}##{id}: #{errors.full_messages.join(', ')}"
      end
    end
  end

  def regenerate_unsubscribe_token
    generate_unsubscribe_token
  end
end 
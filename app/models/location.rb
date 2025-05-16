class Location < ApplicationRecord
  belongs_to :business

  validates :name, presence: true
  validates :address, presence: true
  validates :city, presence: true
  validates :state, presence: true
  validates :zip, presence: true
  validates :hours, presence: true

  # Callbacks to ensure hours is properly stored
  before_validation :ensure_hours_is_hash
  
  # Parse hours to a hash if it's a string
  def ensure_hours_is_hash
    if self.hours.is_a?(String)
      begin
        self.hours = JSON.parse(self.hours)
      rescue JSON::ParserError => e
        Rails.logger.error "[LOCATION] Error parsing hours JSON: #{e.message}"
        # Default to empty hash if parsing fails
        self.hours = {} unless self.hours.is_a?(Hash)
      end
    end
    
    # Ensure hours is a hash 
    self.hours = {} unless self.hours.is_a?(Hash)
  end
  
  # Prevent double-serialization when displaying hours
  def display_hours
    hours.is_a?(String) ? hours : hours.to_json
  end
end 
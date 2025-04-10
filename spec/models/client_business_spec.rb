# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClientBusiness, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:business) }
  end

  describe 'validations' do
    subject { create(:client_business) } # Use create to ensure uniqueness check works
    
    it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:business_id).with_message("is already associated with this business") }
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StaffMember, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:business) }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to have_many(:bookings) }
  end

  describe 'validations' do
    let(:business) { create(:business) }
    subject { build(:staff_member, business: business) }
    
    it { is_expected.to validate_presence_of(:name) }
  end

  describe 'scopes' do
    let(:business) { create(:business) }
    let!(:active_staff) { create(:staff_member, active: true, business: business) }
    let!(:inactive_staff) { create(:staff_member, active: false, business: business) }
    
    it '.active returns only active staff members' do
      expect(StaffMember.active).to include(active_staff)
      expect(StaffMember.active).not_to include(inactive_staff)
    end
  end
end 
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
    
    it '.active returns only active staff members' do
      active_staff = create(:staff_member, active: true, business: business)
      inactive_staff = create(:staff_member, active: false, business: business)
      
      expect(StaffMember.active).to include(active_staff)
      expect(StaffMember.active).not_to include(inactive_staff)
    end
  end

  describe '#available_at?', clean_strategy: :truncation do
    let!(:business) { create(:business) } # Use let! to ensure business exists
    let(:staff_member) { create(:staff_member, business: business) }
    let(:availability_hash) do
      {
        monday: [{ "start" => "09:00", "end" => "17:00" }],
        tuesday: [], # Off day
        wednesday: [{ "start" => "09:00", "end" => "12:00" }, { "start" => "13:00", "end" => "17:00" }], # Split shift
        thursday: [{ "start" => "09:00", "end" => "17:00" }],
        friday: [{ "start" => "09:00", "end" => "17:00" }],
        saturday: [],
        sunday: [],
        exceptions: {
          "2024-05-20" => [], # Specific Monday off
          "2024-05-22" => [{ "start" => "10:00", "end" => "14:00" }] # Specific Wednesday hours
        }
      }
    end

    # Use around block for tenant context and setup
    around do |example|
      ActsAsTenant.with_tenant(business) do
        # Reload first to ensure we have the right record in this context
        staff_member.reload 
        # Update availability 
        staff_member.update!(availability: availability_hash)
        example.run
      end
    end

    # Test cases using Time.zone.parse for consistency
    let(:monday_10am) { Time.zone.parse("2024-05-13 10:00:00") } # Regular Monday
    let(:monday_8am) { Time.zone.parse("2024-05-13 08:00:00") } # Before hours
    let(:monday_5pm) { Time.zone.parse("2024-05-13 17:00:00") } # At end hour (should be false)
    
    let(:tuesday_10am) { Time.zone.parse("2024-05-14 10:00:00") } # Off day
    
    let(:wednesday_10am) { Time.zone.parse("2024-05-15 10:00:00") } # During first shift
    let(:wednesday_12_30pm) { Time.zone.parse("2024-05-15 12:30:00") } # During lunch break
    let(:wednesday_2pm) { Time.zone.parse("2024-05-15 14:00:00") } # During second shift

    let(:exception_monday_10am) { Time.zone.parse("2024-05-20 10:00:00") } # Exception: Day off
    let(:exception_wednesday_11am) { Time.zone.parse("2024-05-22 11:00:00") } # Exception: Within special hours
    let(:exception_wednesday_9am) { Time.zone.parse("2024-05-22 09:00:00") } # Exception: Outside special hours
    let(:exception_wednesday_2pm) { Time.zone.parse("2024-05-22 14:00:00") } # Exception: At end hour

    it "returns true for times within regular intervals" do
      expect(staff_member.available_at?(monday_10am)).to be true
      expect(staff_member.available_at?(wednesday_10am)).to be true
      expect(staff_member.available_at?(wednesday_2pm)).to be true
    end

    it "returns false for times outside regular intervals" do
      expect(staff_member.available_at?(monday_8am)).to be false
      expect(staff_member.available_at?(monday_5pm)).to be false # Check edge case: < end_time
      expect(staff_member.available_at?(wednesday_12_30pm)).to be false # Lunch break
    end

    it "returns false for days with no intervals (off days)" do
      expect(staff_member.available_at?(tuesday_10am)).to be false
    end

    it "returns false if staff member is inactive" do
      staff_member.update!(active: false)
      expect(staff_member.available_at?(monday_10am)).to be false
    end

    context "with exceptions" do
      it "returns false for times within an exception day off" do
        expect(staff_member.available_at?(exception_monday_10am)).to be false
      end

      it "returns true for times within exception intervals" do
        expect(staff_member.available_at?(exception_wednesday_11am)).to be true
      end

      it "returns false for times outside exception intervals on an exception day" do
        expect(staff_member.available_at?(exception_wednesday_9am)).to be false
        expect(staff_member.available_at?(exception_wednesday_2pm)).to be false # Check edge case
      end
    end
  end
end 
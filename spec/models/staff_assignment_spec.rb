require 'rails_helper'

RSpec.describe StaffAssignment, type: :model do
  let(:business) { FactoryBot.create(:business) }
  let(:staff_user) { FactoryBot.create(:user, role: :staff, business: business) }
  let(:service) { FactoryBot.create(:service, business: business) }

  it "is valid with valid attributes" do
    staff_assignment = StaffAssignment.new(user: staff_user, service: service)
    expect(staff_assignment).to be_valid
  end

  it { should belong_to(:user) }
  it { should belong_to(:service) }

  it "requires a user" do
    staff_assignment = StaffAssignment.new(service: service)
    expect(staff_assignment).to_not be_valid
  end

  it "requires a service" do
    staff_assignment = StaffAssignment.new(user: staff_user)
    expect(staff_assignment).to_not be_valid
  end

  # Add more tests for validations or methods as needed
end

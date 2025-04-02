require 'rails_helper'

RSpec.describe AdminUser, type: :model do
  describe "validations" do
    it "is valid with valid attributes" do
      admin_user = AdminUser.new(
        email: "test@example.com",
        password: "password123",
        password_confirmation: "password123"
      )
      expect(admin_user).to be_valid
    end

    it "is not valid without an email" do
      admin_user = AdminUser.new(
        password: "password123",
        password_confirmation: "password123"
      )
      expect(admin_user).not_to be_valid
    end

    it "is not valid with an invalid email format" do
      admin_user = AdminUser.new(
        email: "invalid-email",
        password: "password123",
        password_confirmation: "password123"
      )
      expect(admin_user).not_to be_valid
    end

    it "is not valid when password confirmation doesn't match" do
      admin_user = AdminUser.new(
        email: "test@example.com",
        password: "password123",
        password_confirmation: "different"
      )
      expect(admin_user).not_to be_valid
    end
  end

  describe "devise modules" do
    it "includes expected devise modules" do
      expect(AdminUser.devise_modules).to include(:database_authenticatable)
      expect(AdminUser.devise_modules).to include(:recoverable)
      expect(AdminUser.devise_modules).to include(:rememberable)
      expect(AdminUser.devise_modules).to include(:validatable)
    end
  end
end

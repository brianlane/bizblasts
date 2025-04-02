require 'rails_helper'

RSpec.describe "Admin Companies", type: :request do
  let!(:company) { create(:company, name: "Test Company", subdomain: "testcompany") }
  
  describe "ActiveAdmin configuration" do
    it "has ActiveAdmin configured correctly" do
      expect(defined?(ActiveAdmin)).to be_truthy
      expect(ActiveAdmin.application).to be_a(ActiveAdmin::Application)
    end
    
    it "has AdminUser model" do
      expect(defined?(AdminUser)).to eq("constant")
      expect(AdminUser).to respond_to(:find_by)
    end
    
    it "has Company model" do
      expect(defined?(Company)).to eq("constant")
      expect(Company.count).to be >= 1
    end
  end
  
  describe "authentication" do
    it "redirects non-authenticated users to login" do
      get "/admin"
      expect(response).to redirect_to('/users/sign_in')
    end
  end

  describe "database operations" do
    it "can create a company through direct database operations" do
      company_count = Company.count
      new_company = Company.create!(name: "New Test Company", subdomain: "newtest")
      expect(Company.count).to eq(company_count + 1)
      expect(new_company.persisted?).to be true
      expect(new_company.name).to eq("New Test Company")
    end
    
    it "can update a company through direct database operations" do
      company.update!(name: "Updated Name")
      expect(company.reload.name).to eq("Updated Name")
    end
    
    it "can delete a company through direct database operations" do
      company_to_delete = create(:company, name: "Deletable")
      company_count = Company.count
      company_to_delete.destroy
      expect(Company.count).to eq(company_count - 1)
      expect(Company.find_by(id: company_to_delete.id)).to be_nil
    end
  end
end 
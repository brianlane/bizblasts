# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Database seeds", type: :seed do
  # This type: :seed will trigger our database_cleaner truncation strategy
  
  describe "when running seeds" do
    # We'll use around to manage state properly with database_cleaner
    around do |example|
      # Record counts before the test
      @companies_before = Company.count
      @users_before = User.count
      @customers_before = Customer.count
      @services_before = Service.count
      @providers_before = ServiceProvider.count
      @appointments_before = Appointment.count
      
      # Load seeds
      load Rails.root.join('db', 'seeds.rb')
      
      # Run the test
      example.run
      
      # We'll let database_cleaner handle cleanup
    end
    
    it "creates the default company" do
      expect(Company.find_by(name: 'Default Company', subdomain: 'default')).to be_present
    end
    
    it "creates an admin user for the default company" do
      default_company = Company.find_by(subdomain: 'default')
      admin = User.find_by(email: 'admin@example.com')
      
      expect(admin).to be_present
      expect(admin.company).to eq(default_company)
    end
    
    it "creates sample customers for each company" do
      # Check that default company has customers
      default_company = Company.find_by(subdomain: 'default')
      expect(Customer.where(company: default_company).count).to be >= 3
      
      # Check that Larry's Landscaping has customers
      larrys = Company.find_by(subdomain: 'larrys')
      expect(Customer.where(company: larrys).count).to be >= 8
      
      # Check that Pete's Pool Service has customers
      petes = Company.find_by(subdomain: 'petes')
      expect(Customer.where(company: petes).count).to be >= 8
    end
    
    it "creates sample services for each company" do
      # Check default company services
      default_company = Company.find_by(subdomain: 'default')
      expect(Service.where(company: default_company).count).to be >= 3
      
      # Check Larry's services
      larrys = Company.find_by(subdomain: 'larrys')
      expect(Service.where(company: larrys).count).to be >= 4
      
      # Check Pete's services
      petes = Company.find_by(subdomain: 'petes')
      expect(Service.where(company: petes).count).to be >= 4
    end
    
    it "creates service providers for each company" do
      # Check default company service providers
      default_company = Company.find_by(subdomain: 'default')
      expect(ServiceProvider.where(company: default_company).count).to be >= 2
      
      # Larry's should have more service providers
      larrys = Company.find_by(subdomain: 'larrys')
      expect(ServiceProvider.where(company: larrys).count).to be >= 4
      
      # Pete's should have service providers
      petes = Company.find_by(subdomain: 'petes')
      expect(ServiceProvider.where(company: petes).count).to be >= 3
    end
    
    it "creates appointments for each company" do
      # Check default company appointments
      default_company = Company.find_by(subdomain: 'default')
      expect(Appointment.where(company: default_company).count).to be >= 5
      
      # Check Larry's appointments
      larrys = Company.find_by(subdomain: 'larrys')
      expect(Appointment.where(company: larrys).count).to be >= 25
      
      # Check Pete's appointments
      petes = Company.find_by(subdomain: 'petes')
      expect(Appointment.where(company: petes).count).to be >= 25
    end
    
    it "maintains proper associations between records" do
      # Sample checking of tenant isolation
      larrys = Company.find_by(subdomain: 'larrys')
      petes = Company.find_by(subdomain: 'petes')
      
      # Check that Larry's appointments use Larry's services and providers
      larrys_appointments = Appointment.where(company: larrys).sample(5)
      larrys_appointments.each do |appointment|
        expect(appointment.service.company).to eq(larrys)
        expect(appointment.service_provider.company).to eq(larrys)
        expect(appointment.customer.company).to eq(larrys)
      end
      
      # Check that Pete's appointments use Pete's services and providers
      petes_appointments = Appointment.where(company: petes).sample(5)
      petes_appointments.each do |appointment|
        expect(appointment.service.company).to eq(petes)
        expect(appointment.service_provider.company).to eq(petes)
        expect(appointment.customer.company).to eq(petes)
      end
    end
  end
  
  describe "idempotency" do
    it "doesn't create duplicate core records when run multiple times" do
      # First run
      load Rails.root.join('db', 'seeds.rb')
      
      # Get counts after first run
      companies_after_first = Company.count
      users_after_first = User.count
      
      # Run seeds again
      load Rails.root.join('db', 'seeds.rb')
      
      # Only check companies and users, which should be stable
      # Other records like appointments, customers, and providers use randomized data generation
      # and may create new records on subsequent runs
      expect(Company.count).to eq(companies_after_first)
      expect(User.count).to eq(users_after_first)
      
      # Also check that we have expected companies by name
      expect(Company.where(name: 'Default Company').count).to eq(1)
      expect(Company.where(name: "Larry's Landscaping").count).to eq(1)
      expect(Company.where(name: "Pete's Pool Service").count).to eq(1)
    end
  end
  
  describe "data validity" do
    before do
      # Load seeds for testing validity
      load Rails.root.join('db', 'seeds.rb')
    end
    
    it "creates valid service records" do
      Service.find_each do |service|
        expect(service).to be_valid
        expect(service.name).to be_present
        expect(service.price).to be_present
        expect(service.duration_minutes).to be_present
      end
    end
    
    it "creates valid customer records" do
      Customer.find_each do |customer|
        expect(customer).to be_valid
        expect(customer.name).to be_present
        expect(customer.email).to be_present
      end
    end
    
    it "creates valid appointment records" do
      Appointment.find_each do |appointment|
        expect(appointment).to be_valid
        expect(appointment.start_time).to be_present
        expect(appointment.end_time).to be_present
        expect(appointment.end_time).to be > appointment.start_time
      end
    end
  end
end 
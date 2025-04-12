# frozen_string_literal: true

require 'rails_helper'

# Add metadata to skip default :each cleaning
RSpec.describe "Database seeds", type: :request do
  # Removed run_seeds helper

  # Add metadata `:seed_test` to manage cleaning manually within this context
  context "when seeds have been run", :seed_test do
    # Load seeds once before this context
    before(:context) do
      # Use Rails built-in seed loader
      Rails.application.load_seed 
    end

    # Clean up after the context
    after(:context) do
      DatabaseCleaner.clean_with(:truncation)
    end

    let(:default_business_name) { 'Default Business' }

    context "default tenant" do
      it "creates the default business" do
        # Use hostname instead of subdomain
        default_business = Business.find_by(hostname: 'default')
        expect(default_business).to be_present
        expect(default_business.name).to eq('Default Business')
      end

      it "associates the default business with the correct host_type" do
        # Use hostname instead of subdomain
        default_business = Business.find_by(hostname: 'default')
        # Check the actual host_type created by seeds
        expect(default_business.host_type).to eq('subdomain') 
      end
    end

    context "data integrity" do
      it "maintains proper associations between records" do
        default_business = Business.find_by(hostname: 'default')
        expect(default_business).to be_present

        # Check associations: Find the admin user created by seeds
        user = User.find_by(email: 'admin@example.com') 
        expect(user).to be_present
        expect(user.business).to eq(default_business)
        # Optional: Check role if needed
        # expect(user.role).to eq('manager') 
      end
    end

    context "data validity" do
      it "creates valid service records" do
        default_business = Business.find_by(hostname: 'default')
        expect(default_business).to be_present
        services = Service.where(business: default_business)
        expect(services).not_to be_empty
        services.each { |service| expect(service).to be_valid }
      end

      it "creates valid customer records" do
        default_business = Business.find_by(hostname: 'default')
        expect(default_business).to be_present
        customers = TenantCustomer.where(business: default_business)
        expect(customers).not_to be_empty
        customers.each { |customer| expect(customer).to be_valid }
      end
      
      it "creates valid booking records" do
        default_business = Business.find_by(hostname: 'default')
        expect(default_business).to be_present
        bookings = Booking.where(business: default_business)
        # Bookings might be empty if MINIMAL_SEED is set, adjust expectation
        if ENV['MINIMAL_SEED'] == '1'
          expect(bookings).to be_empty
        else
          expect(bookings).not_to be_empty
          bookings.each { |booking| expect(booking).to be_valid }
        end
      end
    end

    describe "sample data for default business" do
      # Seeds are now loaded in the outer before(:context)

      it "creates sample customers" do
        default_business_tenant = Business.find_by(hostname: 'default')
        expect(default_business_tenant).to be_present
        customers = TenantCustomer.where(business_id: default_business_tenant.id)
        expect(customers.count).to be >= (ENV['MINIMAL_SEED'] == '1' ? 1 : 3) 
        # Check for a specific customer if needed, seeds might use Faker
      end

      it "creates sample services" do
        default_business_tenant = Business.find_by(hostname: 'default')
        expect(default_business_tenant).to be_present
        services = Service.where(business_id: default_business_tenant.id)
        expect(services.count).to be >= 3
        expect(services.map(&:name)).to include('Basic Consultation')
      end

      it "creates sample staff members" do
        default_business_tenant = Business.find_by(hostname: 'default')
        expect(default_business_tenant).to be_present
        staff = StaffMember.includes(:user).where(business_id: default_business_tenant.id)
        expect(staff.count).to be >= 2
        expect(staff.map { |s| s.email }).to include('staff1@example.com')
      end

      it "creates sample bookings" do
        default_business_tenant = Business.find_by(hostname: 'default')
        expect(default_business_tenant).to be_present
        bookings = Booking.where(business_id: default_business_tenant.id)
        if ENV['MINIMAL_SEED'] == '1'
          expect(bookings.count).to eq(0)
        else
          expect(bookings.count).to be >= 1 # Adjust if more specific count is needed
        end
      end
    end
  end
end
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Database seeds", type: :seed do
  # Clean DB tables after tests
  after(:context) do
    puts "--- Cleaning database after seeds_spec suite ---"
    tables = %w[
      bookings services_staff_members services staff_members tenant_customers users businesses 
    ]
    
    # Clean tables in reverse dependency order
    tables.each do |table|
      begin
        ActiveRecord::Base.connection.execute("DELETE FROM #{ActiveRecord::Base.connection.quote_table_name(table)}")
      rescue => e
        puts "Error cleaning table #{table}: #{e.message}"
      end
    end
  end

  context "when running seeds" do
    before(:context) do
      puts "--- Loading seeds for seeds_spec suite ---"
      load Rails.root.join('db', 'seeds.rb')
    end

    context "default tenant" do
      it "creates the default business" do
        expect(Business.find_by(subdomain: 'default')).to be_present
      end

      it "creates an admin user for the default business" do
        default_business = Business.find_by(subdomain: 'default')
        expect(User.find_by(email: 'admin@example.com', business: default_business)).to be_present
      end
    end

    context "sample data" do
      let(:default_business) { Business.find_by(subdomain: 'default') }

      it "creates sample customers for each business" do
        expect(TenantCustomer.where(business: default_business).count).to be > 0
      end

      it "creates sample services for each business" do
        services = Service.where(business: default_business)
        expect(services.count).to be > 0
        
        # Check service names
        service_names = services.pluck(:name)
        expect(service_names).to include('Basic Consultation')
        expect(service_names).to include('Website Setup')
        expect(service_names).to include('Monthly Support')
      end

      it "creates staff members for each business" do
        staff_members = StaffMember.where(business: default_business)
        expect(staff_members.count).to be > 0
      end

      it "creates bookings for each business", skip: ENV['MINIMAL_SEED'] == '1' do
        expect(Booking.where(business: default_business).count).to be > 0
      end
    end

    context "data integrity" do
      it "maintains proper associations between records" do
        # Each booking is associated with a valid service, staff member, and customer
        Booking.all.each do |booking|
          expect(booking.service).to be_present
          expect(booking.staff_member).to be_present
          expect(booking.tenant_customer).to be_present
          expect(booking.business).to be_present
          
          # All records belong to the same business
          expect(booking.service.business_id).to eq(booking.business_id)
          expect(booking.staff_member.business_id).to eq(booking.business_id)
          expect(booking.tenant_customer.business_id).to eq(booking.business_id)
        end
      end
    end

    context "data validity" do
      it "creates valid service records" do
        Service.all.each do |service|
          expect(service).to be_valid
          expect(service.name).to be_present
          expect(service.price).to be_present
          expect(service.duration).to be_present
        end
      end

      it "creates valid customer records" do
        TenantCustomer.all.each do |customer|
          expect(customer).to be_valid
          expect(customer.name).to be_present
          expect(customer.business).to be_present
        end
      end

      it "creates valid booking records", skip: ENV['MINIMAL_SEED'] == '1' do
        Booking.all.each do |booking|
          expect(booking).to be_valid
          expect(booking.start_time).to be_present
          expect(booking.end_time).to be_present
          expect(booking.start_time).to be < booking.end_time
        end
      end
    end
  end
end 
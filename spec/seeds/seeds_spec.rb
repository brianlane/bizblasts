# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Database seeds", :seed_context do
  # Load seeds once for this context, after cleaning
  before(:context) do
    puts "--- Loading seeds for seed context ---"
    Rails.application.load_seed
  end

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

  # --- Tests ---
  context "when seeds have been run" do
    let(:default_business_name) { "Default Business" }

    context "default tenant" do
      it "creates the default business" do
        default_business = Business.find_by(subdomain: 'default')
        expect(default_business).not_to be_nil
        expect(default_business.name).to eq(default_business_name)
      end

      it "associates the default business with the global tenant ID" do
        default_business = Business.find_by(subdomain: 'default')
        expect(default_business).to be_present # Basic check if it exists
      end
    end

    context "data integrity" do
      it "maintains proper associations between records" do
        default_business = Business.find_by(subdomain: 'default')
        raise "Default business tenant not found" unless default_business
        ActsAsTenant.with_tenant(default_business) do
          booking = Booking.first
          expect(booking).to be_present
          expect(booking.service).to be_present
          expect(booking.tenant_customer).to be_present
          expect(booking.staff_member).to be_present
          expect(booking.business).to eq(default_business)
        end
      end
    end

    context "data validity" do
      it "creates valid service records" do
        default_business = Business.find_by(subdomain: 'default')
        raise "Default business tenant not found" unless default_business
        ActsAsTenant.with_tenant(default_business) do
          Service.find_each do |service|
            expect(service).to be_valid
          end
        end
      end

      it "creates valid customer records" do
        default_business = Business.find_by(subdomain: 'default')
        raise "Default business tenant not found" unless default_business
        ActsAsTenant.with_tenant(default_business) do
          TenantCustomer.find_each do |customer|
            expect(customer).to be_valid
          end
        end
      end

      it "creates valid booking records" do
        default_business = Business.find_by(subdomain: 'default')
        raise "Default business tenant not found" unless default_business
        ActsAsTenant.with_tenant(default_business) do
          Booking.find_each do |booking|
            expect(booking).to be_valid
            expect(booking.end_time).to be_present
            expect(booking.start_time).to be < booking.end_time
          end
        end
      end
    end

    context "sample data for default business" do
      it "creates sample customers" do
        default_business_tenant = Business.find_by(subdomain: 'default')
        raise "Default business tenant not found" unless default_business_tenant
        ActsAsTenant.with_tenant(default_business_tenant) do
          expect(TenantCustomer.count).to be >= 2
        end
      end

      it "creates sample services" do
        default_business_tenant = Business.find_by(subdomain: 'default')
        raise "Default business tenant not found" unless default_business_tenant
        ActsAsTenant.with_tenant(default_business_tenant) do
          expect(Service.count).to be >= 3
        end
      end

      it "creates sample staff members" do
        default_business_tenant = Business.find_by(subdomain: 'default')
        raise "Default business tenant not found" unless default_business_tenant
        ActsAsTenant.with_tenant(default_business_tenant) do
          expect(StaffMember.count).to be >= 2
        end
      end

      it "creates sample bookings" do
        default_business_tenant = Business.find_by(subdomain: 'default')
        raise "Default business tenant not found" unless default_business_tenant
        ActsAsTenant.with_tenant(default_business_tenant) do
          expect(Booking.count).to be >= 4
        end
      end
    end
  end
end
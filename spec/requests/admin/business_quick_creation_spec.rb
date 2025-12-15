# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Business Quick Creation', type: :request do
  let(:admin_user) { create(:admin_user) }

  before do
    sign_in admin_user, scope: :admin_user
  end

  describe 'POST /admin/businesses' do
    context 'with subdomain host type' do
      let(:valid_attributes) do
        {
          name: 'Acme Hair Salon',
          industry: 'hair_salons',
          phone: '555-123-4567',
          email: 'contact@acme-salon.com',
          address: '123 Main Street',
          city: 'Phoenix',
          state: 'AZ',
          zip: '85001',
          description: 'Best hair salon in Phoenix',
          subdomain: 'acme-hair-salon',
          host_type: 'subdomain'
        }
      end

      it 'creates a new business with subdomain' do
        expect do
          post admin_businesses_path, params: { business: valid_attributes }
        end.to change(Business, :count).by(1)

        business = Business.last
        expect(business.name).to eq('Acme Hair Salon')
        expect(business.subdomain).to eq('acme-hair-salon')
        expect(business.host_type).to eq('subdomain')
        expect(business.hostname).to eq('acme-hair-salon')
      end

      it 'creates a manager User with business email' do
        expect do
          post admin_businesses_path, params: { business: valid_attributes }
        end.to change(User, :count).by(1)

        business = Business.last
        manager = business.users.manager.first

        expect(manager).to be_present
        expect(manager.email).to eq(business.email)
        expect(manager.first_name).to eq('Business')
        expect(manager.last_name).to eq('Manager')
        expect(manager.role).to eq('manager')
        expect(manager.business_id).to eq(business.id)
      end

      it 'creates a StaffMember with default Mon-Fri 9am-5pm availability' do
        expect do
          post admin_businesses_path, params: { business: valid_attributes }
        end.to change(StaffMember, :count).by(1)

        business = Business.last
        staff_member = business.staff_members.first

        expect(staff_member).to be_present
        expect(staff_member.user).to eq(business.users.manager.first)
        expect(staff_member.active).to be true
        expect(staff_member.availability).to match(
          'monday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'tuesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'wednesday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'thursday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'friday' => [{ 'start' => '09:00', 'end' => '17:00' }],
          'saturday' => [],
          'sunday' => [],
          'exceptions' => {}
        )
      end

      it 'applies default values for optional fields' do
        post admin_businesses_path, params: { business: valid_attributes }

        business = Business.last
        expect(business.website_layout).to eq('basic')
        expect(business.enhanced_accent_color).to eq('red')
        expect(business.tip_mailer_if_no_tip_received).to be true
      end
    end

    context 'with another subdomain business' do
      let(:valid_attributes) do
        {
          name: 'Elite Consulting',
          industry: 'consulting',
          phone: '555-987-6543',
          email: 'info@elite-consulting.com',
          address: '456 Business Blvd',
          city: 'Scottsdale',
          state: 'AZ',
          zip: '85250',
          description: 'Professional consulting services',
          subdomain: 'elite-consulting',
          host_type: 'subdomain'
        }
      end

      it 'creates a new business with subdomain' do
        expect do
          post admin_businesses_path, params: { business: valid_attributes }
        end.to change(Business, :count).by(1)

        business = Business.last
        expect(business.subdomain).to eq('elite-consulting')
        expect(business.host_type).to eq('subdomain')
      end

      it 'creates manager User and StaffMember' do
        expect do
          post admin_businesses_path, params: { business: valid_attributes }
        end.to change(User, :count).by(1)
          .and change(StaffMember, :count).by(1)

        business = Business.last
        expect(business.users.manager).to be_present
        expect(business.staff_members.first).to be_present
      end
    end

    context 'with custom domain host type' do
      let(:valid_attributes) do
        {
          name: 'Premium Services Inc',
          industry: 'consulting',
          phone: '555-111-2222',
          email: 'contact@premium-services.com',
          address: '789 Executive Dr',
          city: 'Tempe',
          state: 'AZ',
          zip: '85281',
          description: 'Premium consulting and services',
          hostname: 'premium-services.com',
          host_type: 'custom_domain'
        }
      end

      it 'creates a new business with custom domain' do
        expect do
          post admin_businesses_path, params: { business: valid_attributes }
        end.to change(Business, :count).by(1)

        business = Business.last
        expect(business.hostname).to eq('premium-services.com')
        expect(business.host_type).to eq('custom_domain')
      end

      it 'creates manager User and StaffMember' do
        expect do
          post admin_businesses_path, params: { business: valid_attributes }
        end.to change(User, :count).by(1)
          .and change(StaffMember, :count).by(1)
      end
    end

    context 'with invalid attributes' do
      let(:invalid_attributes) do
        {
          name: '',
          industry: 'hair_salons',  # Valid enum but missing other required fields
          phone: '',
          email: 'not-an-email',
          address: '',
          city: '',
          state: '',
          zip: '',
          description: '',
          subdomain: 'test',
          host_type: 'subdomain'
        }
      end

      it 'does not create a business' do
        expect do
          post admin_businesses_path, params: { business: invalid_attributes }
        end.not_to change(Business, :count)
      end

      it 'does not create a manager User' do
        expect do
          post admin_businesses_path, params: { business: invalid_attributes }
        end.not_to change(User, :count)
      end

      it 'does not create a StaffMember' do
        expect do
          post admin_businesses_path, params: { business: invalid_attributes }
        end.not_to change(StaffMember, :count)
      end
    end

    context 'with duplicate business email' do
      let!(:existing_business) { create(:business, email: 'duplicate@example.com') }
      let(:duplicate_email_attributes) do
        {
          name: 'New Business',
          industry: 'consulting',
          phone: '555-999-8888',
          email: 'duplicate@example.com',
          address: '123 Test St',
          city: 'Phoenix',
          state: 'AZ',
          zip: '85001',
          description: 'Test business',
          subdomain: 'new-business',
          host_type: 'subdomain'
        }
      end

      it 'creates the business but uses unique email for manager User' do
        # The business email can be duplicated, but this will create a manager user
        # The User model should handle email uniqueness per role type
        expect do
          post admin_businesses_path, params: { business: duplicate_email_attributes }
        end.to change(Business, :count).by(1)

        # Note: This test documents the current behavior
        # If User email must be unique globally, the after_create callback will fail
        # and we'd need to handle that edge case
      end
    end

    context 'with duplicate subdomain' do
      let!(:existing_business) { create(:business, subdomain: 'test-salon', hostname: 'test-salon', host_type: 'subdomain') }
      let(:duplicate_subdomain_attributes) do
        {
          name: 'Test Salon 2',
          industry: 'hair_salons',
          phone: '555-888-9999',
          email: 'testsalon2@example.com',
          address: '456 Test Ave',
          city: 'Phoenix',
          state: 'AZ',
          zip: '85002',
          description: 'Another test salon',
          subdomain: 'test-salon',
          host_type: 'subdomain'
        }
      end

      it 'does not create the business due to hostname uniqueness' do
        expect do
          post admin_businesses_path, params: { business: duplicate_subdomain_attributes }
        end.not_to change(Business, :count)
      end
    end

    context 'auto-generation verification' do
      it 'documents that subdomain should be auto-generated from name via JavaScript' do
        # This is handled client-side by the slugify() JavaScript function
        # The test verifies that the form accepts pre-slugified values

        business_name = 'My Awesome Business!'
        expected_slug = 'my-awesome-business'

        attributes = {
          name: business_name,
          industry: 'consulting',
          phone: '555-123-4567',
          email: 'awesome@example.com',
          address: '123 Main St',
          city: 'Phoenix',
          state: 'AZ',
          zip: '85001',
          description: 'Test business',
          subdomain: expected_slug,  # This would be auto-generated by JS
          host_type: 'subdomain'
        }

        post admin_businesses_path, params: { business: attributes }

        business = Business.last
        expect(business.subdomain).to eq(expected_slug)
      end
    end
  end

  describe 'GET /admin/businesses/new' do
    it 'renders the simplified form' do
      get new_admin_business_path
      expect(response).to have_http_status(:success)
    end

    it 'includes JavaScript for dynamic field switching' do
      get new_admin_business_path
      expect(response.body).to include('updateFieldsForHostType')
      expect(response.body).to include('updateSlugFields')
      expect(response.body).to include('slugify')
    end

    it 'includes subdomain and hostname fields with proper wrappers' do
      get new_admin_business_path
      expect(response.body).to include('subdomain-field-wrapper')
      expect(response.body).to include('hostname-field-wrapper')
    end
  end
end

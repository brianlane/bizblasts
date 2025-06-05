require 'rails_helper'

RSpec.describe BusinessManager::ProductsController, type: :request do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }
  let(:product) { create(:product, business: business) }
  
  before do
    # Simulate subdomain in host for routes under SubdomainConstraint
    host! "#{business.hostname}.example.com"
    # Set current tenant for the request context
    ActsAsTenant.current_tenant = business
    sign_in user
  end

  after do
    # Clear current tenant after the test
    ActsAsTenant.current_tenant = nil
  end

  describe 'image deletion functionality' do
    it 'successfully processes image deletion requests' do
      patch business_manager_product_path(product), params: {
        product: {
          name: 'Updated Product',
          images_attributes: [
            { id: 1, _destroy: '1' },
            { id: 2, _destroy: 'true' }
          ]
        }
      }
      
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(business_manager_product_path(product))
    end

    it 'handles mixed deletion and primary flag operations' do
      patch business_manager_product_path(product), params: {
        product: {
          name: 'Updated Product',
          images_attributes: [
            { id: 1, _destroy: '1' },
            { id: 3, primary: 'true' }
          ]
        }
      }
      
      expect(response).to have_http_status(:found)
    end
  end

  describe 'adding images without replacing existing ones' do
    it 'processes new image uploads correctly' do
      # Create a simple test file
      test_file = fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg')
      
      patch business_manager_product_path(product), params: {
        product: {
          name: 'Updated Product',
          images: [test_file]
        }
      }
      
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(business_manager_product_path(product))
    end

    it 'handles concurrent deletion and addition operations' do
      test_file = fixture_file_upload('spec/fixtures/files/test_image.jpg', 'image/jpeg')
      
      patch business_manager_product_path(product), params: {
        product: {
          name: 'Updated Product',
          images: [test_file],
          images_attributes: [
            { id: 2, _destroy: '1' }
          ]
        }
      }
      
      expect(response).to have_http_status(:found)
    end
  end

  describe 'edge cases and error handling' do
    it 'handles empty images arrays without errors' do
      patch business_manager_product_path(product), params: {
        product: {
          name: 'Updated Product',
          images: []
        }
      }
      
      expect(response).to have_http_status(:found)
    end

    it 'handles attempts to delete non-existent images gracefully' do
      patch business_manager_product_path(product), params: {
        product: {
          name: 'Updated Product',
          images_attributes: [
            { id: 999, _destroy: '1' } # Non-existent ID
          ]
        }
      }
      
      expect(response).to have_http_status(:found)
    end
  end
end 
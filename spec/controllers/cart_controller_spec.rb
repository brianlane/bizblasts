require 'rails_helper'

RSpec.describe Public::CartsController, type: :controller do
  let!(:business) { create(:business, subdomain: 'testtenant', hostname: 'testtenant') }

  before do
    business.save! unless business.persisted?
    ActsAsTenant.current_tenant = business
    set_tenant(business)
  end

  describe 'GET #show' do
    it 'returns success' do
      @request.host = 'testtenant.lvh.me'
      get :show
      expect(response).to be_successful
    end
    it 'assigns @cart' do
      @request.host = 'testtenant.lvh.me'
      get :show
      expect(assigns(:cart)).to be_a(Hash)
    end
  end
end 
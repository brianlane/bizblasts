require 'rails_helper'

RSpec.describe BusinessManager::Settings::TipsController, type: :controller do
  let(:business) { create(:business, subdomain: 'testbiz', hostname: 'testbiz', tier: 'free') }
  let(:manager_user) { create(:user, :manager, business: business) }
  let(:staff_user) { create(:user, :staff, business: business) }

  before do
    request.host = "#{business.subdomain}.example.com"
    ActsAsTenant.current_tenant = business
  end

  describe 'GET #show' do
    context 'when authenticated as business manager' do
      before { sign_in manager_user }

      it 'renders the tips settings page' do
        get :show
        
        expect(response).to have_http_status(:ok)
        expect(assigns(:business)).to eq(business)
        expect(assigns(:tip_configuration)).to be_present
        expect(response).to render_template(:show)
      end
    end

    context 'when authenticated as staff' do
      before { sign_in staff_user }

      it 'redirects with unauthorized message' do
        get :show
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end
    end

    context 'when not authenticated' do
      it 'redirects to sign in' do
        get :show
        
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'PATCH #update' do
    context 'when authenticated as business manager' do
      before { sign_in manager_user }

      context 'with valid parameters' do
        it 'enables tips successfully' do
          patch :update, params: { business: { tips_enabled: true } }
          
          expect(business.reload.tips_enabled?).to be true
          expect(response).to redirect_to(business_manager_settings_tips_path)
          expect(flash[:notice]).to eq('Tips settings updated successfully.')
        end

        it 'disables tips successfully' do
          business.update!(tips_enabled: true)
          
          patch :update, params: { business: { tips_enabled: false } }
          
          expect(business.reload.tips_enabled?).to be false
          expect(response).to redirect_to(business_manager_settings_tips_path)
          expect(flash[:notice]).to eq('Tips settings updated successfully.')
        end

        it 'handles checkbox unchecked (tips_enabled: "0")' do
          business.update!(tips_enabled: true)
          
          patch :update, params: { business: { tips_enabled: "0" } }
          
          expect(business.reload.tips_enabled?).to be false
          expect(response).to redirect_to(business_manager_settings_tips_path)
          expect(flash[:notice]).to eq('Tips settings updated successfully.')
        end
      end

      context 'with invalid parameters' do
        before do
          # Mock validation failure - our controller now uses update! which raises an exception
          allow_any_instance_of(Business).to receive(:update!).and_raise(
            ActiveRecord::RecordInvalid.new(business.tap { |b| b.errors.add(:base, 'Some error') })
          )
          # Mock the tip_configuration_or_default method
          allow_any_instance_of(Business).to receive(:tip_configuration_or_default).and_return(
            double('TipConfiguration', persisted?: false)
          )
        end

        it 'renders show template with error message' do
          patch :update, params: { business: { tips_enabled: true } }
          
          expect(response).to render_template(:show)
          expect(flash[:alert]).to include('Unable to update tips settings')
        end
      end
    end

    context 'when authenticated as staff' do
      before { sign_in staff_user }

      it 'redirects with unauthorized message' do
        patch :update, params: { business: { tips_enabled: true } }
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
        expect(business.reload.tips_enabled?).to be false
      end
    end

    context 'when not authenticated' do
      it 'redirects to sign in' do
        patch :update, params: { business: { tips_enabled: true } }
        
        expect(response).to redirect_to(new_user_session_path)
        expect(business.reload.tips_enabled?).to be false
      end
    end
  end

  describe 'parameter filtering' do
    before { sign_in manager_user }

    it 'only permits tips_enabled parameter' do
      patch :update, params: { 
        business: { 
          tips_enabled: true,
          name: 'Hacked Name',
          tier: 'premium'
        } 
      }
      
      business.reload
      expect(business.tips_enabled?).to be true
      expect(business.name).not_to eq('Hacked Name')
      expect(business.tier).not_to eq('premium')
    end
  end
end 
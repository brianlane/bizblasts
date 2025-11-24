require 'rails_helper'

RSpec.describe BusinessManager::Settings::TipsController, type: :controller do
  let(:business) { create(:business, tier: 'free') }
  let(:user) { create(:user, :manager, business: business) }
  let(:staff_user) { create(:user, :staff, business: business) }
  let!(:manager_staff_member) { create(:staff_member, user: user, business: business) }
  let!(:staff_staff_member) { create(:staff_member, user: staff_user, business: business) }
  let!(:product) { create(:product, business: business, tips_enabled: false) }
  let!(:service) { create(:service, business: business, tips_enabled: false) }

  before do
    request.host = host_for(business)
    ActsAsTenant.current_tenant = business
  end

  describe 'GET #show' do
    context 'when authenticated as business manager' do
      before { sign_in user }

      it 'renders the tips settings page' do
        get :show
        expect(response).to have_http_status(:success)
        expect(response).to render_template(:show)
        expect(assigns(:business)).to eq(business)
        expect(assigns(:tip_configuration)).to be_present
      end
    end

    context 'when authenticated as staff' do
      before { sign_in staff_user }

      it 'redirects with unauthorized message' do
        get :show
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to access this page.')
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
      before { sign_in user }

      context 'with valid parameters' do
        it 'updates product tip settings successfully' do
          patch :update, params: { 
            products: { 
              product.id => { tips_enabled: '1' } 
            }
          }
          
          expect(response).to redirect_to(business_manager_settings_tips_path)
          expect(flash[:notice]).to eq('Tips settings updated successfully.')
          expect(product.reload.tips_enabled).to be true
        end

        it 'updates service tip settings successfully' do
          patch :update, params: { 
            services: { 
              service.id => { tips_enabled: '1' } 
            }
          }
          
          expect(response).to redirect_to(business_manager_settings_tips_path)
          expect(flash[:notice]).to eq('Tips settings updated successfully.')
          expect(service.reload.tips_enabled).to be true
        end

        it 'updates tip configuration successfully' do
          patch :update, params: { 
            tip_configuration: {
              custom_tip_enabled: '1',
              tip_message: 'Thank you for your business!',
              default_tip_percentages: ['15', '18', '20']
            }
          }
          
          expect(response).to redirect_to(business_manager_settings_tips_path)
          expect(flash[:notice]).to eq('Tips settings updated successfully.')
        end
      end

      context 'with invalid parameters' do
        it 'renders show template with error message' do
          allow_any_instance_of(Product).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(product))
          allow(product).to receive_message_chain(:errors, :full_messages).and_return(['Invalid field'])
          
          patch :update, params: { 
            products: { 
              product.id => { tips_enabled: '1' } 
            }
          }
          
          expect(response).to render_template(:show)
          expect(flash.now[:alert]).to include('Unable to update tips settings')
        end
      end
    end

    context 'when authenticated as staff' do
      before { sign_in staff_user }

      it 'redirects with unauthorized message' do
        patch :update, params: { 
          products: { 
            product.id => { tips_enabled: '1' } 
          }
        }
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('You are not authorized to access this page.')
      end
    end

    context 'when not authenticated' do
      it 'redirects to sign in' do
        patch :update, params: { 
          products: { 
            product.id => { tips_enabled: '1' } 
          }
        }
        
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'parameter filtering' do
    before { sign_in user }

    it 'only permits allowed parameters' do
      expect(controller).to receive(:product_tip_params).at_least(:once).and_call_original
      expect(controller).to receive(:service_tip_params).at_least(:once).and_call_original
      expect(controller).to receive(:tip_configuration_params).at_least(:once).and_call_original
      
      patch :update, params: { 
        products: { product.id.to_s => { tips_enabled: '1' } },
        services: { service.id.to_s => { tips_enabled: '1' } },
        tip_configuration: { custom_tip_enabled: '1' },
        forbidden_param: 'should_not_be_permitted'
      }
    end
  end
end 
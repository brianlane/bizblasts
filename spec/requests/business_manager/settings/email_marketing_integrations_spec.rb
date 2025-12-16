# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Email Marketing Integrations', type: :request do
  let(:business) { create(:business) }
  let(:manager) { create(:user, :manager, business: business) }

  before do
    sign_in manager
    host! "#{business.subdomain}.#{Rails.application.config.main_domain}"
  end

  describe 'GET /manage/settings/integrations' do
    it 'includes email marketing section' do
      get business_manager_settings_integrations_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Email Marketing')
    end

    context 'with mailchimp connection' do
      let!(:mailchimp_connection) do
        create(:email_marketing_connection, :mailchimp, :with_list, business: business)
      end

      it 'shows the connected mailchimp account' do
        get business_manager_settings_integrations_path

        expect(response.body).to include('Mailchimp')
        expect(response.body).to include('Connected')
        expect(response.body).to include(mailchimp_connection.account_email)
      end
    end

    context 'with constant contact connection' do
      let!(:cc_connection) do
        create(:email_marketing_connection, :constant_contact, :with_list, business: business)
      end

      it 'shows the connected constant contact account' do
        get business_manager_settings_integrations_path

        expect(response.body).to include('Constant Contact')
        expect(response.body).to include('Connected')
        expect(response.body).to include(cc_connection.account_email)
      end
    end
  end

  describe 'GET /manage/settings/integrations/mailchimp/oauth/authorize' do
    context 'when credentials are configured' do
      before do
        allow(MailchimpOauthCredentials).to receive(:configured?).and_return(true)
        allow(MailchimpOauthCredentials).to receive(:client_id).and_return('test_client_id')
        allow(MailchimpOauthCredentials).to receive(:authorize_url).and_return('https://login.mailchimp.com/oauth2/authorize')
      end

      it 'redirects to Mailchimp authorization' do
        get mailchimp_oauth_authorize_business_manager_settings_integrations_path

        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('login.mailchimp.com')
      end
    end

    context 'when credentials are not configured' do
      before do
        allow(MailchimpOauthCredentials).to receive(:configured?).and_return(false)
      end

      it 'redirects with an alert' do
        get mailchimp_oauth_authorize_business_manager_settings_integrations_path

        expect(response).to redirect_to(business_manager_settings_integrations_path)
        follow_redirect!
        expect(response.body).to include('not configured')
      end
    end
  end

  describe 'DELETE /manage/settings/integrations/mailchimp/disconnect' do
    let!(:connection) { create(:email_marketing_connection, :mailchimp, business: business) }

    it 'disconnects the mailchimp integration' do
      expect {
        delete mailchimp_disconnect_business_manager_settings_integrations_path
      }.to change(EmailMarketingConnection, :count).by(-1)

      expect(response).to redirect_to(business_manager_settings_integrations_path)
    end
  end

  describe 'GET /manage/settings/integrations/constant-contact/oauth/authorize' do
    context 'when credentials are configured' do
      before do
        allow(ConstantContactOauthCredentials).to receive(:configured?).and_return(true)
        allow(ConstantContactOauthCredentials).to receive(:client_id).and_return('test_client_id')
        allow(ConstantContactOauthCredentials).to receive(:scopes).and_return('contact_data offline_access')
        allow(ConstantContactOauthCredentials).to receive(:authorize_url).and_return('https://authz.constantcontact.com/oauth2/default/v1/authorize')
      end

      it 'redirects to Constant Contact authorization' do
        get constant_contact_oauth_authorize_business_manager_settings_integrations_path

        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('constantcontact.com')
      end
    end
  end

  describe 'DELETE /manage/settings/integrations/constant-contact/disconnect' do
    let!(:connection) { create(:email_marketing_connection, :constant_contact, business: business) }

    it 'disconnects the constant contact integration' do
      expect {
        delete constant_contact_disconnect_business_manager_settings_integrations_path
      }.to change(EmailMarketingConnection, :count).by(-1)

      expect(response).to redirect_to(business_manager_settings_integrations_path)
    end
  end

  describe 'POST /manage/settings/integrations/email-marketing/:provider/sync' do
    let!(:connection) { create(:email_marketing_connection, :mailchimp, :with_list, business: business) }

    it 'queues a sync job' do
      expect {
        post email_marketing_sync_business_manager_settings_integrations_path(provider: 'mailchimp')
      }.to have_enqueued_job(EmailMarketing::SyncContactsJob)

      expect(response).to redirect_to(business_manager_settings_integrations_path)
    end
  end

  describe 'PATCH /manage/settings/integrations/email-marketing/:provider/config' do
    let!(:connection) { create(:email_marketing_connection, :mailchimp, business: business) }

    it 'updates the connection settings' do
      patch email_marketing_update_config_business_manager_settings_integrations_path(provider: 'mailchimp'),
            params: {
              email_marketing_connection: {
                sync_on_customer_create: true,
                sync_on_customer_update: false
              }
            }

      expect(response).to redirect_to(business_manager_settings_integrations_path)
      connection.reload
      expect(connection.sync_on_customer_create).to be true
      expect(connection.sync_on_customer_update).to be false
    end
  end

  describe 'GET /manage/settings/integrations/email-marketing/:provider/lists' do
    let!(:connection) { create(:email_marketing_connection, :mailchimp, :with_list, business: business) }

    it 'returns available lists as JSON' do
      mock_lists = [{ id: 'list1', name: 'Main List', member_count: 100 }]
      allow_any_instance_of(EmailMarketingConnection).to receive(:available_lists).and_return(mock_lists)

      get email_marketing_lists_business_manager_settings_integrations_path(provider: 'mailchimp')

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['lists']).to eq(mock_lists.as_json)
    end
  end

  describe 'GET /manage/settings/integrations/email-marketing/:provider/sync-status' do
    let!(:connection) { create(:email_marketing_connection, :mailchimp, business: business, last_synced_at: 1.hour.ago, total_contacts_synced: 50) }
    let!(:sync_log) { create(:email_marketing_sync_log, :completed, email_marketing_connection: connection, business: business) }

    it 'returns sync status as JSON' do
      get email_marketing_sync_status_business_manager_settings_integrations_path(provider: 'mailchimp')

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json['connected']).to be true
      expect(json['total_contacts_synced']).to eq(50)
      expect(json['recent_syncs']).to be_present
    end
  end
end

require 'rails_helper'

RSpec.describe 'Business Manager Setup Reminder', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:business) { create(:business, subdomain: 'testsubdomain') }
  let(:user) { create(:user, :manager, business: business) }

  before do
    # Bypass the subdomain constraint in tests
    allow(SubdomainConstraint).to receive(:matches?).and_return(true)
    sign_in user
  end

  describe 'DELETE /manage/setup_reminder' do
    it 'creates a dismissal and returns no content' do
      expect {
        delete business_manager_setup_reminder_url(key: 'configure_tax_rates', host: "#{business.subdomain}.lvh.me")
      }.to change(SetupReminderDismissal, :count).by(1)
      expect(response).to have_http_status(:no_content)
      dismissal = SetupReminderDismissal.last
      expect(dismissal.user).to eq(user)
      expect(dismissal.task_key).to eq('configure_tax_rates')
      expect(dismissal.dismissed_at).to be_within(1.second).of(Time.current)
    end

    it 'is idempotent for the same key' do
      user.setup_reminder_dismissals.create!(task_key: 'configure_tax_rates', dismissed_at: 1.hour.ago)
      expect {
        delete business_manager_setup_reminder_url(key: 'configure_tax_rates', host: "#{business.subdomain}.lvh.me")
      }.not_to change(SetupReminderDismissal, :count)
      expect(response).to have_http_status(:no_content)
    end
  end
end 
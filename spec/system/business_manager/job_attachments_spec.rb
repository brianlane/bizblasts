# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Job Attachments Management', type: :system do
  let(:business) { create(:business, :with_owner) }
  let(:user) { business.users.find_by(role: :manager) || create(:user, :manager, business: business) }
  let(:service) { create(:service, business: business, name: 'Test Service') }

  before do
    driven_by(:rack_test)
    sign_in user
  end

  describe 'viewing attachments on a service' do
    it 'displays attachments list' do
      attachment = create(:job_attachment, business: business, attachable: service, title: 'Setup Instructions')

      visit business_manager_service_job_attachments_path(service)

      expect(page).to have_content('Setup Instructions')
    end

    it 'shows attachment type badges' do
      create(:job_attachment, business: business, attachable: service, attachment_type: :before_photo, title: 'Before Shot')
      create(:job_attachment, :instruction, business: business, attachable: service, title: 'Instructions')

      visit business_manager_service_job_attachments_path(service)

      expect(page).to have_content('Before Shot')
      expect(page).to have_content('Instructions')
    end
  end

  describe 'adding an attachment to a service' do
    it 'creates a new attachment' do
      visit business_manager_service_job_attachments_path(service)

      click_link 'Add Attachment'

      fill_in 'Title', with: 'New Attachment'
      fill_in 'Description', with: 'A detailed description'
      select 'General', from: 'Attachment type'
      select 'Internal', from: 'Visibility'

      click_button 'Upload'

      expect(page).to have_content('New Attachment')
    end
  end

  describe 'updating an attachment' do
    let(:attachment) { create(:job_attachment, business: business, attachable: service, title: 'Original Title') }

    it 'updates the attachment details' do
      visit edit_business_manager_service_job_attachment_path(service, attachment)

      fill_in 'Title', with: 'Updated Title'
      click_button 'Update'

      expect(page).to have_content('Updated Title')
    end
  end

  describe 'deleting an attachment' do
    let!(:attachment) { create(:job_attachment, business: business, attachable: service, title: 'To Delete') }

    it 'removes the attachment' do
      visit business_manager_service_job_attachments_path(service)

      accept_confirm do
        within("tr", text: 'To Delete') do
          click_link 'Delete'
        end
      end

      expect(page).not_to have_content('To Delete')
    end
  end

  describe 'job attachments on bookings' do
    let(:booking) { create(:booking, business: business, service: service) }

    it 'allows adding before photos' do
      attachment = create(:job_attachment, business: business, attachable: booking, attachment_type: :before_photo, title: 'Before Photo')

      visit business_manager_booking_job_attachments_path(booking)

      expect(page).to have_content('Before Photo')
    end

    it 'allows adding after photos' do
      attachment = create(:job_attachment, :after_photo, business: business, attachable: booking, title: 'After Photo')

      visit business_manager_booking_job_attachments_path(booking)

      expect(page).to have_content('After Photo')
    end
  end

  describe 'job attachments on estimates' do
    let(:estimate) { create(:estimate, business: business) }

    it 'allows adding reference files' do
      attachment = create(:job_attachment, business: business, attachable: estimate, attachment_type: :reference_file, title: 'Project Specs')

      visit business_manager_estimate_job_attachments_path(estimate)

      expect(page).to have_content('Project Specs')
    end
  end

  describe 'visibility settings' do
    it 'shows internal attachments to staff' do
      internal = create(:job_attachment, business: business, attachable: service, visibility: :internal, title: 'Staff Only Notes')

      visit business_manager_service_job_attachments_path(service)

      expect(page).to have_content('Staff Only Notes')
      expect(page).to have_content('Internal')
    end

    it 'marks customer-visible attachments' do
      visible = create(:job_attachment, :customer_visible, business: business, attachable: service, title: 'Customer Guidelines')

      visit business_manager_service_job_attachments_path(service)

      expect(page).to have_content('Customer Guidelines')
      expect(page).to have_content('Customer Visible')
    end
  end
end

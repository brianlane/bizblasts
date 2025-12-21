# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Job Attachments Management', type: :system do
  include_context 'setup business context'

  let(:service) { create(:service, business: business, name: 'Test Service') }

  before do
    driven_by(:rack_test)
    sign_in manager
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
    it 'shows the add attachment form' do
      visit business_manager_service_job_attachments_path(service)

      # The page should have the inline form for adding attachments
      expect(page).to have_content('Add New Attachment')
      expect(page).to have_button('Add Attachment')
    end
  end

  describe 'deleting an attachment' do
    let!(:attachment) { create(:job_attachment, business: business, attachable: service, title: 'To Delete') }

    it 'has a delete button for the attachment' do
      visit business_manager_service_job_attachments_path(service)

      expect(page).to have_content('To Delete')
      # Verify the delete button exists (actual deletion requires JS confirmation)
      expect(page).to have_selector("[data-attachment-id='#{attachment.id}'] button[title='Delete']")
    end
  end

  describe 'job attachments on bookings' do
    let(:booking) { create(:booking, business: business, service: service) }

    it 'allows viewing before photos' do
      attachment = create(:job_attachment, business: business, attachable: booking, attachment_type: :before_photo, title: 'Before Photo')

      visit business_manager_booking_job_attachments_path(booking)

      expect(page).to have_content('Before Photo')
      expect(page).to have_content('Before photo')
    end

    it 'allows viewing after photos' do
      attachment = create(:job_attachment, :after_photo, business: business, attachable: booking, title: 'After Photo')

      visit business_manager_booking_job_attachments_path(booking)

      expect(page).to have_content('After Photo')
    end
  end

  describe 'job attachments on estimates' do
    let(:estimate) { create(:estimate, business: business) }

    it 'allows viewing reference files' do
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
    end

    it 'marks customer-visible attachments' do
      visible = create(:job_attachment, :customer_visible, business: business, attachable: service, title: 'Customer Guidelines')

      visit business_manager_service_job_attachments_path(service)

      expect(page).to have_content('Customer Guidelines')
      expect(page).to have_content('Customer visible')
    end
  end
end

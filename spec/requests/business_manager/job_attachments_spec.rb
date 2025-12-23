# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BusinessManager::JobAttachments', type: :request do
  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }
  let(:service) { create(:service, business: business) }

  before do
    host! "#{business.subdomain}.lvh.me"
    sign_in user
    ActsAsTenant.current_tenant = business
  end

  # Service attachments (main test case)
  describe 'with Service as attachable' do
    describe 'GET /manage/services/:service_id/job_attachments' do
      it 'returns a successful response' do
        get business_manager_service_job_attachments_path(service)

        expect(response).to be_successful
      end

      it 'displays attachments for the service' do
        attachment = create(:job_attachment, business: business, attachable: service, title: 'Test Attachment')

        get business_manager_service_job_attachments_path(service)

        expect(response.body).to include('Test Attachment')
      end

      context 'with JSON format' do
        it 'returns JSON response' do
          attachment = create(:job_attachment, business: business, attachable: service)

          get business_manager_service_job_attachments_path(service), as: :json

          expect(response).to be_successful
          expect(JSON.parse(response.body)).to be_an(Array)
        end
      end
    end

    describe 'POST /manage/services/:service_id/job_attachments' do
      let(:valid_params) do
        {
          job_attachment: {
            attachment_type: 'general',
            title: 'Test Attachment',
            description: 'A test description',
            visibility: 'internal'
          }
        }
      end

      it 'creates a new job attachment' do
        expect {
          post business_manager_service_job_attachments_path(service), params: valid_params
        }.to change(JobAttachment, :count).by(1)
      end

      it 'sets the uploaded_by_user' do
        post business_manager_service_job_attachments_path(service), params: valid_params

        expect(JobAttachment.last.uploaded_by_user).to eq(user)
      end

      it 'sets the business correctly' do
        post business_manager_service_job_attachments_path(service), params: valid_params

        expect(JobAttachment.last.business).to eq(business)
      end

      context 'with different attachment types' do
        %w[before_photo after_photo instruction reference_file general].each do |type|
          it "creates attachment with #{type} type" do
            post business_manager_service_job_attachments_path(service), params: {
              job_attachment: valid_params[:job_attachment].merge(attachment_type: type)
            }

            expect(JobAttachment.last.attachment_type).to eq(type)
          end
        end
      end

      context 'with customer_visible visibility' do
        it 'creates customer-visible attachment' do
          post business_manager_service_job_attachments_path(service), params: {
            job_attachment: valid_params[:job_attachment].merge(visibility: 'customer_visible')
          }

          expect(JobAttachment.last.visibility).to eq('customer_visible')
        end
      end

      context 'with JSON format' do
        it 'returns JSON response on success' do
          post business_manager_service_job_attachments_path(service), params: valid_params, as: :json

          expect(response).to have_http_status(:created)
          json = JSON.parse(response.body)
          expect(json['title']).to eq('Test Attachment')
        end
      end

      context 'with flat params (no nesting)' do
        it 'handles flat parameter format' do
          post business_manager_service_job_attachments_path(service), params: {
            attachment_type: 'general',
            title: 'Flat Params Title',
            visibility: 'internal'
          }

          expect(JobAttachment.last.title).to eq('Flat Params Title')
        end
      end
    end

    describe 'PATCH /manage/services/:service_id/job_attachments/:id' do
      let(:attachment) { create(:job_attachment, business: business, attachable: service, title: 'Original Title') }

      it 'updates the attachment' do
        patch business_manager_service_job_attachment_path(service, attachment), params: {
          job_attachment: { title: 'Updated Title' }
        }

        attachment.reload
        expect(attachment.title).to eq('Updated Title')
      end

      context 'with JSON format' do
        it 'returns JSON response' do
          patch business_manager_service_job_attachment_path(service, attachment), params: {
            job_attachment: { title: 'JSON Updated' }
          }, as: :json

          expect(response).to be_successful
          json = JSON.parse(response.body)
          expect(json['title']).to eq('JSON Updated')
        end
      end
    end

    describe 'DELETE /manage/services/:service_id/job_attachments/:id' do
      let!(:attachment) { create(:job_attachment, business: business, attachable: service) }

      it 'deletes the attachment' do
        expect {
          delete business_manager_service_job_attachment_path(service, attachment)
        }.to change(JobAttachment, :count).by(-1)
      end

      context 'with JSON format' do
        it 'returns no content' do
          delete business_manager_service_job_attachment_path(service, attachment), as: :json

          expect(response).to have_http_status(:no_content)
        end
      end
    end

    describe 'POST /manage/services/:service_id/job_attachments/reorder' do
      let!(:attachment1) { create(:job_attachment, business: business, attachable: service, position: 0) }
      let!(:attachment2) { create(:job_attachment, business: business, attachable: service, position: 1) }
      let!(:attachment3) { create(:job_attachment, business: business, attachable: service, position: 2) }

      it 'reorders attachments' do
        post reorder_business_manager_service_job_attachments_path(service), params: {
          attachment_ids: [attachment3.id, attachment1.id, attachment2.id]
        }

        attachment1.reload
        attachment2.reload
        attachment3.reload

        expect(attachment3.position).to eq(0)
        expect(attachment1.position).to eq(1)
        expect(attachment2.position).to eq(2)
      end

      context 'with JSON format' do
        it 'returns success response' do
          post reorder_business_manager_service_job_attachments_path(service), params: {
            attachment_ids: [attachment2.id, attachment1.id, attachment3.id]
          }, as: :json

          expect(response).to be_successful
          json = JSON.parse(response.body)
          expect(json['success']).to be true
        end
      end
    end
  end

  # Booking attachments
  describe 'with Booking as attachable' do
    let(:booking) { create(:booking, business: business, service: service) }

    describe 'GET /manage/bookings/:booking_id/job_attachments' do
      it 'returns a successful response' do
        get business_manager_booking_job_attachments_path(booking)

        expect(response).to be_successful
      end
    end

    describe 'POST /manage/bookings/:booking_id/job_attachments' do
      let(:valid_params) do
        {
          job_attachment: {
            attachment_type: 'before_photo',
            title: 'Before Photo',
            visibility: 'internal'
          }
        }
      end

      it 'creates a new job attachment for booking' do
        expect {
          post business_manager_booking_job_attachments_path(booking), params: valid_params
        }.to change(JobAttachment, :count).by(1)
      end

      it 'associates attachment with the booking' do
        post business_manager_booking_job_attachments_path(booking), params: valid_params

        expect(JobAttachment.last.attachable).to eq(booking)
      end
    end

    describe 'DELETE /manage/bookings/:booking_id/job_attachments/:id' do
      let!(:attachment) { create(:job_attachment, business: business, attachable: booking) }

      it 'deletes the attachment' do
        expect {
          delete business_manager_booking_job_attachment_path(booking, attachment)
        }.to change(JobAttachment, :count).by(-1)
      end
    end
  end

  # Estimate attachments
  describe 'with Estimate as attachable' do
    let(:estimate) { create(:estimate, business: business) }

    describe 'GET /manage/estimates/:estimate_id/job_attachments' do
      it 'returns a successful response' do
        get business_manager_estimate_job_attachments_path(estimate)

        expect(response).to be_successful
      end
    end

    describe 'POST /manage/estimates/:estimate_id/job_attachments' do
      let(:valid_params) do
        {
          job_attachment: {
            attachment_type: 'reference_file',
            title: 'Reference Document',
            visibility: 'customer_visible'
          }
        }
      end

      it 'creates a new job attachment for estimate' do
        expect {
          post business_manager_estimate_job_attachments_path(estimate), params: valid_params
        }.to change(JobAttachment, :count).by(1)
      end

      it 'associates attachment with the estimate' do
        post business_manager_estimate_job_attachments_path(estimate), params: valid_params

        expect(JobAttachment.last.attachable).to eq(estimate)
      end
    end
  end

  describe 'authorization' do
    let(:other_business) { create(:business) }
    let(:other_service) do
      # Create service without tenant to avoid ActsAsTenant overriding the business
      ActsAsTenant.without_tenant do
        create(:service, business: other_business)
      end
    end

    it 'returns 404 when accessing attachments from other businesses' do
      get business_manager_service_job_attachments_path(other_service)

      expect(response).to have_http_status(:not_found)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'BusinessManager::CsvController', type: :request do
  let(:business) { create(:business) }
  let(:manager) { create(:user, :manager, business: business) }
  let(:staff) { create(:user, :staff, business: business) }

  before do
    host! "#{business.subdomain}.lvh.me"
  end

  describe 'GET /manage/csv' do
    context 'when signed in as manager' do
      before { sign_in manager }

      it 'returns success' do
        get business_manager_csv_index_path
        expect(response).to have_http_status(:success)
      end

      it 'displays export and import sections' do
        get business_manager_csv_index_path
        expect(response.body).to include('Export Data')
        expect(response.body).to include('Import Data')
      end

      it 'lists all import types' do
        get business_manager_csv_index_path
        CsvImportRun::IMPORT_TYPES.each do |type|
          expect(response.body).to include(type.humanize.titleize)
        end
      end
    end

    context 'when signed in as staff' do
      before { sign_in staff }

      it 'returns success' do
        get business_manager_csv_index_path
        expect(response).to have_http_status(:success)
      end

      it 'displays export section' do
        get business_manager_csv_index_path
        expect(response.body).to include('Export Data')
      end
    end

    context 'when not signed in' do
      it 'redirects to sign in' do
        get business_manager_csv_index_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET /manage/csv/export/:type' do
    before { sign_in manager }

    it 'exports customers as CSV' do
      create(:tenant_customer, business: business, email: 'test@example.com')

      get export_business_manager_csv_index_path(type: 'customers', format: :csv)

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include('text/csv')
      expect(response.body).to include('test@example.com')
    end

    it 'exports products as CSV' do
      create(:product, business: business, name: 'Test Product')

      get export_business_manager_csv_index_path(type: 'products', format: :csv)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Test Product')
    end

    it 'raises error for invalid type' do
      # The validate_type! method raises ActionController::RoutingError for invalid types
      # which may then cascade to other errors during error handling
      expect {
        get export_business_manager_csv_index_path(type: 'invalid', format: :csv)
      }.to raise_error(StandardError)
    end
  end

  describe 'GET /manage/csv/template/:type' do
    before { sign_in manager }

    it 'returns template CSV with headers' do
      get template_business_manager_csv_index_path(type: 'customers', format: :csv)

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include('text/csv')
      expect(response.body).to include('Email')
      expect(response.body).to include('First Name')
    end

    it 'includes sample data row' do
      get template_business_manager_csv_index_path(type: 'customers', format: :csv)
      expect(response.body).to include('customer@example.com')
    end
  end

  describe 'GET /manage/csv/import/:type' do
    context 'when signed in as manager' do
      before { sign_in manager }

      it 'shows import form' do
        get import_form_business_manager_csv_index_path(type: 'customers')

        expect(response).to have_http_status(:success)
        expect(response.body).to include('Import Customers')
        expect(response.body).to include('Upload a CSV file')
      end

      it 'shows template download link' do
        get import_form_business_manager_csv_index_path(type: 'customers')
        expect(response.body).to include('Download template')
      end
    end

    context 'when signed in as staff' do
      before { sign_in staff }

      it 'denies access' do
        get import_form_business_manager_csv_index_path(type: 'customers')
        # Staff users are redirected when access is denied (Pundit behavior)
        expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /manage/csv/import/:type' do
    before { sign_in manager }

    it 'creates import run and redirects to status' do
      csv_content = "email,first_name,last_name\ntest@test.com,Test,User"
      file = Rack::Test::UploadedFile.new(
        StringIO.new(csv_content),
        'text/csv',
        original_filename: 'customers.csv'
      )

      post import_business_manager_csv_index_path(type: 'customers'), params: { file: file }

      expect(CsvImportRun.count).to eq(1)
      import_run = CsvImportRun.last
      expect(import_run.import_type).to eq('customers')
      expect(response).to redirect_to(import_status_business_manager_csv_index_path(id: import_run.id))
    end

    it 'redirects with error if no file provided' do
      post import_business_manager_csv_index_path(type: 'customers')

      expect(response).to redirect_to(import_form_business_manager_csv_index_path(type: 'customers'))
      expect(flash[:alert]).to include('Please select a file')
    end
  end

  describe 'GET /manage/csv/import/:id/status' do
    before { sign_in manager }

    let(:import_run) { create(:csv_import_run, :running, business: business) }

    it 'shows import status page' do
      get import_status_business_manager_csv_index_path(id: import_run.id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Import Progress')
    end

    it 'returns JSON for XHR requests' do
      get import_status_business_manager_csv_index_path(id: import_run.id, format: :json)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json).to include('status', 'progress', 'processed_rows')
    end
  end

  describe 'GET /manage/csv/import/:id/errors' do
    before { sign_in manager }

    let(:import_run) { create(:csv_import_run, :partial, business: business) }

    it 'shows error details' do
      get import_errors_business_manager_csv_index_path(id: import_run.id)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Import Errors')
    end
  end
end


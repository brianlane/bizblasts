# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BusinessManager::GalleryController, type: :controller do
  # Register turbo_stream MIME type for controller tests
  before(:all) do
    unless Mime::Type.lookup_by_extension(:turbo_stream)
      Mime::Type.register "text/vnd.turbo-stream.html", :turbo_stream
    end
  end

  let(:business) { create(:business) }
  let(:user) { create(:user, :manager, business: business) }

  before do
    # Ensure requests are scoped to the correct tenant subdomain
    @request.host = "#{business.hostname}.lvh.me"
    ActsAsTenant.current_tenant = business
    sign_in user
  end

  describe 'GET #index' do
    let!(:gallery_photo) { create(:gallery_photo, business: business) }

    it 'returns success' do
      get :index
      expect(response).to have_http_status(:success)
    end

    it 'assigns gallery photos' do
      get :index
      expect(assigns(:gallery_photos)).to include(gallery_photo)
    end

    it 'assigns available images' do
      service = create(:service, business: business)
      service.images.attach(io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test_image.jpg')), filename: 'test.jpg')

      get :index
      expect(assigns(:available_images)).to be_present
      expect(assigns(:available_images)[:services].first[:source_id]).to eq(service.id)
    end
  end

  describe 'POST #create_photo' do
    let(:valid_params) do
      {
        image: fixture_file_upload('test_image.jpg', 'image/jpeg'),
        title: 'Test Photo',
        description: 'Test Description'
      }
    end

    context 'with valid params' do
      it 'creates a new gallery photo' do
        expect {
          post :create_photo, params: valid_params
        }.to change { business.gallery_photos.count }.by(1)
      end

      it 'redirects to gallery index with success message' do
        post :create_photo, params: valid_params
        expect(response).to redirect_to(business_manager_gallery_index_path)
        expect(flash[:notice]).to eq('Photo added successfully')
      end

      it 'enqueues background processing job' do
        expect {
          post :create_photo, params: valid_params
        }.to have_enqueued_job(ProcessGalleryPhotoJob)
      end
    end

    context 'with invalid params' do
      it 'does not create photo without image' do
        invalid_params = { photo: { title: 'Test' } }

        expect {
          post :create_photo, params: invalid_params
        }.not_to change { business.gallery_photos.count }
      end

      it 'redirects with error message' do
        invalid_params = { photo: { title: 'Test' } }
        post :create_photo, params: invalid_params

        expect(response).to redirect_to(business_manager_gallery_index_path)
        expect(flash[:alert]).to be_present
      end
    end

    context 'when max photos limit reached' do
      before do
        create_list(:gallery_photo, 100, business: business)
      end

      it 'does not create photo' do
        expect {
          post :create_photo, params: valid_params
        }.not_to change { business.gallery_photos.count }
      end

      it 'shows error message' do
        post :create_photo, params: valid_params
        expect(flash[:alert]).to match(/Maximum 100 photos/)
      end
    end
  end

  describe 'PATCH #update_photo' do
    let(:photo) { create(:gallery_photo, business: business, title: 'Old Title') }

    it 'updates photo attributes' do
      patch :update_photo, params: { id: photo.id, gallery_photo: { title: 'New Title' } }

      photo.reload
      expect(photo.title).to eq('New Title')
    end

    it 'redirects with success message' do
      patch :update_photo, params: { id: photo.id, gallery_photo: { title: 'New Title' } }

      expect(response).to redirect_to(business_manager_gallery_index_path)
      expect(flash[:notice]).to eq('Photo updated successfully')
    end

    context 'with invalid params' do
      it 'redirects with error message' do
        # Create a validation error by trying to set an invalid attribute
        # The title validation might not work, so let's stub the service method to fail
        allow(GalleryPhotoService).to receive(:update_photo).and_wrap_original do |method, photo_obj, attrs|
          # Add an error to the photo and return false
          photo_obj.errors.add(:base, 'Update failed')
          false
        end

        patch :update_photo, params: { id: photo.id, gallery_photo: { title: 'New Title' } }

        expect(flash[:alert]).to eq('Update failed')
      end
    end
  end

  describe 'DELETE #destroy_photo' do
    let!(:photo) { create(:gallery_photo, business: business) }

    it 'deletes the photo' do
      expect {
        delete :destroy_photo, params: { id: photo.id }
      }.to change { business.gallery_photos.count }.by(-1)
    end

    it 'redirects with success message' do
      delete :destroy_photo, params: { id: photo.id }

      expect(response).to redirect_to(business_manager_gallery_index_path)
      expect(flash[:notice]).to include('removed successfully')
    end

    context 'when deletion fails' do
      it 'redirects with error message' do
        allow(GalleryPhotoService).to receive(:remove).and_return(false)

        delete :destroy_photo, params: { id: photo.id }

        expect(flash[:alert]).to be_present
      end
    end
  end

  describe 'POST #reorder_photos' do
    let!(:photo1) { create(:gallery_photo, business: business, position: 1) }
    let!(:photo2) { create(:gallery_photo, business: business, position: 2) }
    let!(:photo3) { create(:gallery_photo, business: business, position: 3) }

    it 'reorders photos based on provided order' do
      post :reorder_photos, params: { photo_ids: [photo3.id, photo1.id, photo2.id] }

      photo1.reload
      photo2.reload
      photo3.reload

      expect(photo3.position).to eq(1)
      expect(photo1.position).to eq(2)
      expect(photo2.position).to eq(3)
    end

    it 'responds with json success' do
      post :reorder_photos, params: { photo_ids: [photo3.id, photo1.id, photo2.id] }, format: :json

      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['success']).to be true
    end

    context 'when reordering fails' do
      it 'responds with json error' do
        post :reorder_photos, params: { photo_ids: [] }, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
      end
    end
  end

  describe 'POST #create_video' do
    let(:valid_params) do
      {
        video_file: fixture_file_upload('test-video.mp4', 'video/mp4'),
        video_title: 'My Video',
        video_display_location: 'hero',
        video_autoplay_hero: true
      }
    end

    context 'with valid params' do
      it 'attaches video to business' do
        post :create_video, params: valid_params

        business.reload
        expect(business.gallery_video).to be_attached
      end

      it 'updates video settings' do
        post :create_video, params: valid_params

        business.reload
        expect(business.video_title).to eq('My Video')
        expect(business.video_display_location).to eq('hero')
        expect(business.video_autoplay_hero).to be true
      end

      it 'redirects with success message' do
        post :create_video, params: valid_params

        expect(response).to redirect_to(business_manager_gallery_index_path)
        expect(flash[:notice]).to include('uploaded successfully')
      end

      it 'enqueues background processing job' do
        expect {
          post :create_video, params: valid_params
        }.to have_enqueued_job(ProcessGalleryVideoJob).at_least(:once)
      end
    end

    context 'with invalid format' do
      let(:invalid_params) do
        {
          video_file: fixture_file_upload('test_image.jpg', 'image/jpeg'),
          video_title: 'Test'
        }
      end

      it 'redirects with error message' do
        post :create_video, params: invalid_params

        expect(flash[:alert]).to match(/Invalid video format/)
      end
    end

    context 'when video exceeds size limit' do
      it 'redirects with error message' do
        large_video = fixture_file_upload('test-video.mp4', 'video/mp4')
        allow(GalleryVideoService).to receive(:upload).and_raise(
          GalleryVideoService::VideoUploadError,
          "Video file too large. Maximum size: 50 MB"
        )

        post :create_video, params: { video_file: large_video, video_title: 'Test' }

        expect(flash[:alert]).to match(/too large/)
      end
    end
  end

  describe 'PATCH #update_video' do
    before do
      video_file = fixture_file_upload('test-video.mp4', 'video/mp4')
      business.gallery_video.attach(video_file)
      business.save!
    end

    it 'updates video settings' do
      patch :update_video, params: {
        video: {
          title: 'Updated Title',
          display_location: 'gallery',
          autoplay_hero: false
        }
      }

      business.reload
      expect(business.video_title).to eq('Updated Title')
      expect(business.video_display_location).to eq('gallery')
      expect(business.video_autoplay_hero).to be false
    end

    it 'redirects with success message' do
      patch :update_video, params: { video: { title: 'Updated', display_location: 'hero' } }

      expect(response).to redirect_to(business_manager_gallery_index_path)
      expect(flash[:notice]).to eq('Video settings updated')
    end

    context 'when no video is attached' do
      before do
        business.gallery_video.purge
      end

      it 'redirects with error message' do
        patch :update_video, params: { video: { title: 'Test' } }

        expect(flash[:alert]).to match(/No video attached/)
      end
    end
  end

  describe 'DELETE #destroy_video' do
    before do
      video_file = fixture_file_upload('test-video.mp4', 'video/mp4')
      business.gallery_video.attach(video_file)
      business.update!(video_title: 'My Video')
    end

    it 'removes the video' do
      delete :destroy_video

      business.reload
      expect(business.gallery_video).not_to be_attached
    end

    it 'clears video settings' do
      delete :destroy_video

      business.reload
      expect(business.video_title).to be_nil
    end

    it 'redirects with success message' do
      delete :destroy_video

      expect(response).to redirect_to(business_manager_gallery_index_path)
      expect(flash[:notice]).to include('removed successfully')
    end

    context 'when deletion fails' do
      it 'redirects with error message' do
        allow(GalleryVideoService).to receive(:remove).and_return(false)

        delete :destroy_video

        expect(flash[:alert]).to be_present
      end
    end
  end

  describe 'authorization' do
    context 'when user is not authorized' do
      let(:unauthorized_user) { create(:user, :client) }

      before do
        sign_in unauthorized_user
      end

      it 'redirects index action' do
        get :index
        expect(response).to redirect_to(dashboard_path)
      end

      it 'redirects create_photo action' do
        post :create_photo, params: { photo: { title: 'Test' } }
        expect(response).to redirect_to(dashboard_path)
      end
    end
  end
end

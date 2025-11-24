# frozen_string_literal: true

module BusinessManager
  # Controller for managing business gallery photos and videos
  class GalleryController < BusinessManager::BaseController
    before_action :set_business
    before_action :set_gallery_photo, only: %i[update_photo destroy_photo]

    # GET /manage/gallery
    def index
      @gallery_photos = @business.gallery_photos.includes(:source).order(:position)
      @available_images = GalleryPhotoService.available_images_for_gallery(@business)
      @video_info = GalleryVideoService.video_info(@business)
      @photos_count = @gallery_photos.count
      @can_add_more = @photos_count < 100
    end

    # POST /manage/gallery/photos
    def create_photo
      if params[:source_type].present? && params[:source_id].present?
        # Adding from existing service/product image
        create_from_existing
      else
        # Adding from file upload
        create_from_upload
      end
    rescue GalleryPhotoService::MaxPhotosExceededError => e
      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, alert: e.message }
        format.json { render json: { error: e.message }, status: :unprocessable_content }
      end
    rescue StandardError => e
      Rails.logger.error "Failed to create gallery photo: #{e.message}"
      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, alert: 'Failed to add photo to gallery' }
        format.json { render json: { error: e.message }, status: :unprocessable_content }
      end
    end

    # PATCH /manage/gallery/photos/:id
    def update_photo
      attributes = photo_params.to_h.symbolize_keys

      if GalleryPhotoService.update_photo(@gallery_photo, attributes)
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, notice: 'Photo updated successfully' }
          format.json { render json: @gallery_photo, status: :ok }
        end
      else
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: @gallery_photo.errors.full_messages.join(', ') }
          format.json { render json: { errors: @gallery_photo.errors.full_messages }, status: :unprocessable_content }
        end
      end
    end

    # DELETE /manage/gallery/photos/:id
    def destroy_photo
      if GalleryPhotoService.remove(@gallery_photo)
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, notice: 'Photo removed successfully' }
          format.json { head :no_content }
        end
      else
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: 'Failed to remove photo' }
          format.json { render json: { error: 'Failed to remove photo' }, status: :unprocessable_content }
        end
      end
    end

    # POST /manage/gallery/photos/reorder
    def reorder_photos
      photo_ids = params[:photo_ids]

      if photo_ids.present? && GalleryPhotoService.reorder(@business, photo_ids)
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, notice: 'Photos reordered successfully' }
          format.json { render json: { success: true }, status: :ok }
        end
      else
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: 'Failed to reorder photos' }
          format.json { render json: { success: false, error: 'Failed to reorder photos' }, status: :unprocessable_content }
        end
      end
    end

    # POST /manage/gallery/video
    def create_video
      video_file = params[:video_file]
      attributes = {
        video_title: params[:video_title],
        video_display_location: params[:video_display_location] || 'hero',
        video_autoplay_hero: ActiveModel::Type::Boolean.new.cast(params[:video_autoplay_hero])
      }

      GalleryVideoService.upload(@business, video_file, attributes)

      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, notice: 'Video uploaded successfully' }
        format.json { render json: GalleryVideoService.video_info(@business), status: :created }
      end
    rescue GalleryVideoService::VideoUploadError => e
      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, alert: e.message }
        format.json { render json: { error: e.message }, status: :unprocessable_content }
      end
    end

    # PATCH /manage/gallery/video
    def update_video
      # Handle both nested video[...] params and flat params
      video_params = params[:video] || {}

      location = video_params[:display_location].presence || params[:video_display_location].presence
      title = video_params[:title].presence || params[:video_title].presence

      # Build service parameters hash
      service_params = { location: location, title: title }

      # Only include autoplay if explicitly provided (to use service default otherwise)
      if video_params.key?(:autoplay_hero) || params.key?(:video_autoplay_hero)
        autoplay_value = video_params[:autoplay_hero] || params[:video_autoplay_hero]
        service_params[:autoplay] = ActiveModel::Type::Boolean.new.cast(autoplay_value)
      end

      GalleryVideoService.update_display_settings(@business, **service_params)

      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, notice: 'Video settings updated' }
        format.json { render json: GalleryVideoService.video_info(@business), status: :ok }
      end
    rescue GalleryVideoService::VideoNotFoundError, ArgumentError => e
      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, alert: e.message }
        format.json { render json: { error: e.message }, status: :unprocessable_content }
      end
    end

    # DELETE /manage/gallery/video
    def destroy_video
      if GalleryVideoService.remove(@business)
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, notice: 'Video removed successfully' }
          format.json { head :no_content }
        end
      else
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: 'Failed to remove video' }
          format.json { render json: { error: 'Failed to remove video' }, status: :unprocessable_content }
        end
      end
    end

    private

    def set_business
      @business = current_user.business
    end

    def set_gallery_photo
      @gallery_photo = @business.gallery_photos.find(params[:id])
    end

    def create_from_upload
      files = params[:image].is_a?(Array) ? params[:image] : [params[:image]]
      files = files.reject(&:blank?)  # Filter out empty strings from file array
      attributes = {
        title: params[:title],
        description: params[:description]
      }

      @gallery_photos = files.map do |file|
        GalleryPhotoService.add_from_upload(@business, file, attributes)
      end

      count = @gallery_photos.count
      message = count == 1 ? 'Photo added successfully' : "#{count} photos added successfully"

      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, notice: message }
        format.json { render json: @gallery_photos, status: :created }
      end
    end

    def create_from_existing
      @gallery_photo = GalleryPhotoService.add_from_existing(
        @business,
        params[:source_type],
        params[:source_id],
        params[:attachment_id],
        {
          title: params[:title],
          description: params[:description]
        }
      )

      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, notice: 'Photo added from existing image' }
        format.json { render json: @gallery_photo, status: :created }
      end
    end

    def photo_params
      params.require(:gallery_photo).permit(:title, :description)
    end
  end
end

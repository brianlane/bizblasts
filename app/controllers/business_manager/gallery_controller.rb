# frozen_string_literal: true

module BusinessManager
  # Controller for managing business gallery photos and videos
  class GalleryController < BusinessManager::BaseController
    before_action :set_business
    before_action :set_gallery_photo, only: %i[update_photo destroy_photo crop_photo]

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

    # POST /manage/gallery/photos/:id/crop
    def crop_photo
      crop_data = params[:crop_data]

      unless crop_data.present?
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: 'No crop data provided' }
          format.json { render json: { error: 'No crop data provided' }, status: :unprocessable_content }
        end
        return
      end

      # Parse crop data if it's a string
      crop_params = crop_data.is_a?(String) ? JSON.parse(crop_data) : crop_data.to_unsafe_h

      result = ImageCropService.crop_attached_image(
        @gallery_photo,
        :image,
        crop_params
      )

      if result[:success]
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, notice: 'Photo cropped successfully' }
          format.json do
            render json: {
              success: true,
              image_url: @gallery_photo.image_url(:medium)
            }
          end
        end
      else
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: result[:error] }
          format.json { render json: { error: result[:error] }, status: :unprocessable_content }
        end
      end
    rescue JSON::ParserError => e
      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, alert: 'Invalid crop data format' }
        format.json { render json: { error: 'Invalid crop data format' }, status: :unprocessable_content }
      end
    rescue StandardError => e
      Rails.logger.error "Failed to crop gallery photo: #{e.message}"
      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, alert: 'Failed to crop photo' }
        format.json { render json: { error: e.message }, status: :unprocessable_content }
      end
    end

    private

    def set_business
      @business = current_user.business
    end

    def set_gallery_photo
      @gallery_photo = @business.gallery_photos.find(params[:id])
    end

    # Maximum size for a single image (10MB)
    MAX_FILE_SIZE = 10.megabytes

    # Maximum total upload size per batch (25MB)
    MAX_BATCH_SIZE = 25.megabytes

    # Maximum files per batch upload
    MAX_FILES_PER_BATCH = 10

    def create_from_upload
      files = params[:image].is_a?(Array) ? params[:image] : [params[:image]]
      files = files.reject(&:blank?)  # Filter out empty strings from file array

      # Validate that at least one file was provided
      if files.empty?
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: 'Please select at least one image file' }
          format.json { render json: { error: 'No image file provided' }, status: :unprocessable_content }
        end
        return
      end

      # Validate number of files in batch
      if files.count > MAX_FILES_PER_BATCH
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: "Maximum #{MAX_FILES_PER_BATCH} files can be uploaded at once" }
          format.json { render json: { error: "Maximum #{MAX_FILES_PER_BATCH} files per upload" }, status: :unprocessable_content }
        end
        return
      end

      # Calculate total batch size and validate individual files
      total_size = 0
      oversized_files = []
      invalid_files = []

      files.each do |file|
        # Reject files that don't respond to .size rather than silently skipping
        unless file.respond_to?(:size)
          invalid_files << file.original_filename
          next
        end

        file_size = file.size
        total_size += file_size

        if file_size > MAX_FILE_SIZE
          oversized_files << "#{file.original_filename} (#{(file_size / 1.megabyte.to_f).round(1)}MB)"
        end
      end

      # Reject if any files are invalid (don't have size information)
      if invalid_files.any?
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: "Invalid files (missing size information): #{invalid_files.join(', ')}" }
          format.json { render json: { error: "Invalid files", files: invalid_files }, status: :unprocessable_content }
        end
        return
      end

      # Reject if any individual file is too large
      if oversized_files.any?
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: "Files too large (max 10MB each): #{oversized_files.join(', ')}" }
          format.json { render json: { error: "Files exceed 10MB limit", files: oversized_files }, status: :unprocessable_content }
        end
        return
      end

      # Reject if total batch size is too large
      if total_size > MAX_BATCH_SIZE
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: "Total upload size (#{(total_size / 1.megabyte.to_f).round(1)}MB) exceeds 25MB limit. Please upload in smaller batches." }
          format.json { render json: { error: "Total batch size exceeds 25MB limit" }, status: :unprocessable_content }
        end
        return
      end

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

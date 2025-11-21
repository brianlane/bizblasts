# frozen_string_literal: true

module BusinessManager
  # Controller for managing business gallery photos and videos
  class GalleryController < BusinessManager::BaseController
    before_action :set_business
    before_action :set_gallery_photo, only: %i[update_photo destroy_photo]

    # GET /manage/gallery
    def index
      @gallery_photos = @business.gallery_photos.includes(:source).order(:position)
      @featured_photos = @gallery_photos.featured
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
        format.turbo_stream { render turbo_stream: turbo_stream.replace('flash', partial: 'shared/flash', locals: { alert: e.message }) }
      end
    rescue StandardError => e
      Rails.logger.error "Failed to create gallery photo: #{e.message}"
      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, alert: 'Failed to add photo to gallery' }
        format.json { render json: { error: e.message }, status: :unprocessable_content }
        format.turbo_stream { render turbo_stream: turbo_stream.replace('flash', partial: 'shared/flash', locals: { alert: 'Failed to add photo' }) }
      end
    end

    # PATCH /manage/gallery/photos/:id
    def update_photo
      attributes = photo_params.to_h.symbolize_keys

      if GalleryPhotoService.update_photo(@gallery_photo, attributes)
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, notice: 'Photo updated successfully' }
          format.json { render json: @gallery_photo, status: :ok }
          format.turbo_stream { render turbo_stream: turbo_stream.replace("gallery_photo_#{@gallery_photo.id}", partial: 'gallery_photo_card', locals: { photo: @gallery_photo }) }
        end
      else
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: @gallery_photo.errors.full_messages.join(', ') }
          format.json { render json: { errors: @gallery_photo.errors.full_messages }, status: :unprocessable_content }
        end
      end
    rescue GalleryPhotoService::MaxFeaturedPhotosExceededError => e
      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, alert: e.message }
        format.json { render json: { error: e.message }, status: :unprocessable_content }
      end
    end

    # DELETE /manage/gallery/photos/:id
    def destroy_photo
      if GalleryPhotoService.remove(@gallery_photo)
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, notice: 'Photo removed successfully' }
          format.json { head :no_content }
          format.turbo_stream { render turbo_stream: turbo_stream.remove("gallery_photo_#{@gallery_photo.id}") }
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

    # POST /manage/gallery/photos/:id/toggle_featured
    def toggle_featured
      @gallery_photo = @business.gallery_photos.find(params[:id])

      if GalleryPhotoService.toggle_featured(@gallery_photo)
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, notice: 'Photo featured status updated' }
          format.json { render json: { featured: @gallery_photo.featured }, status: :ok }
          format.turbo_stream { render turbo_stream: turbo_stream.replace("gallery_photo_#{@gallery_photo.id}", partial: 'gallery_photo_card', locals: { photo: @gallery_photo }) }
        end
      else
        respond_to do |format|
          format.html { redirect_to business_manager_gallery_index_path, alert: 'Failed to update featured status' }
          format.json { render json: { error: 'Failed to update' }, status: :unprocessable_content }
        end
      end
    rescue GalleryPhotoService::MaxFeaturedPhotosExceededError => e
      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, alert: e.message }
        format.json { render json: { error: e.message }, status: :unprocessable_content }
      end
    end

    # POST /manage/gallery/video
    def create_video
      video_file = params[:video_file]
      attributes = {
        video_title: params[:video_title],
        video_display_location: params[:video_display_location] || 'hero',
        video_autoplay_hero: params[:video_autoplay_hero] != 'false'
      }

      GalleryVideoService.upload(@business, video_file, attributes)

      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, notice: 'Video uploaded successfully' }
        format.json { render json: GalleryVideoService.video_info(@business), status: :created }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace('gallery_video_section', partial: 'gallery_video_section', locals: { business: @business }),
            turbo_stream.replace('flash', partial: 'shared/flash', locals: { notice: 'Video uploaded successfully' })
          ]
        end
      end
    rescue GalleryVideoService::VideoUploadError => e
      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, alert: e.message }
        format.json { render json: { error: e.message }, status: :unprocessable_content }
        format.turbo_stream { render turbo_stream: turbo_stream.replace('flash', partial: 'shared/flash', locals: { alert: e.message }) }
      end
    end

    # PATCH /manage/gallery/video
    def update_video
      # Handle both nested video[...] params and flat params
      video_params = params[:video] || {}

      location = video_params[:display_location].presence || params[:video_display_location].presence
      autoplay = if video_params.key?(:autoplay_hero)
                   video_params[:autoplay_hero] != 'false'
                 else
                   params[:video_autoplay_hero] != 'false'
                 end
      title = video_params[:title].presence || params[:video_title].presence

      GalleryVideoService.update_display_settings(
        @business,
        location: location,
        autoplay: autoplay,
        title: title
      )

      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, notice: 'Video settings updated' }
        format.json { render json: GalleryVideoService.video_info(@business), status: :ok }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace('gallery_video_section', partial: 'gallery_video_section', locals: { business: @business }),
            turbo_stream.replace('flash', partial: 'shared/flash', locals: { notice: 'Video settings updated' })
          ]
        end
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
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.replace('gallery_video_section', partial: 'gallery_video_section', locals: { business: @business }),
              turbo_stream.replace('flash', partial: 'shared/flash', locals: { notice: 'Video removed successfully' })
            ]
          end
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
      file = params[:image]
      attributes = {
        title: params[:title],
        description: params[:description],
        featured: params[:featured] == 'true',
        display_in_hero: params[:display_in_hero] == 'true'
      }

      @gallery_photo = GalleryPhotoService.add_from_upload(@business, file, attributes)

      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, notice: 'Photo added successfully' }
        format.json { render json: @gallery_photo, status: :created }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append('gallery_photos_grid', partial: 'gallery_photo_card', locals: { photo: @gallery_photo }),
            turbo_stream.replace('flash', partial: 'shared/flash', locals: { notice: 'Photo added successfully' })
          ]
        end
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
          description: params[:description],
          featured: params[:featured] == 'true',
          display_in_hero: params[:display_in_hero] == 'true'
        }
      )

      respond_to do |format|
        format.html { redirect_to business_manager_gallery_index_path, notice: 'Photo added from existing image' }
        format.json { render json: @gallery_photo, status: :created }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append('gallery_photos_grid', partial: 'gallery_photo_card', locals: { photo: @gallery_photo }),
            turbo_stream.replace('flash', partial: 'shared/flash', locals: { notice: 'Photo added successfully' })
          ]
        end
      end
    end

    def photo_params
      params.require(:gallery_photo).permit(:title, :description, :featured, :display_in_hero)
    end
  end
end

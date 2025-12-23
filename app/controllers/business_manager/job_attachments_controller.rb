# frozen_string_literal: true

class BusinessManager::JobAttachmentsController < BusinessManager::BaseController
  before_action :set_attachable
  before_action :set_job_attachment, only: [:update, :destroy]

  # GET /manage/job_attachments
  def index
    @job_attachments = @attachable.job_attachments.ordered.includes(:uploaded_by_user, file_attachment: :blob)

    respond_to do |format|
      format.html
      format.json { render json: attachments_json(@job_attachments) }
    end
  end

  # POST /manage/job_attachments
  def create
    @job_attachment = @attachable.job_attachments.build(job_attachment_params)
    @job_attachment.business = current_business
    @job_attachment.uploaded_by_user = current_user

    if @job_attachment.save
      respond_to do |format|
        format.html { redirect_back fallback_location: polymorphic_path([:business_manager, @attachable]), notice: 'Attachment uploaded successfully.' }
        format.turbo_stream
        format.json { render json: attachment_json(@job_attachment), status: :created }
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: polymorphic_path([:business_manager, @attachable]), alert: @job_attachment.errors.full_messages.join(', ') }
        format.turbo_stream { render turbo_stream: turbo_stream.replace('attachment-errors', partial: 'shared/flash', locals: { flash: { alert: @job_attachment.errors.full_messages.join(', ') } }) }
        format.json { render json: { errors: @job_attachment.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /manage/job_attachments/:id
  def update
    if @job_attachment.update(job_attachment_params)
      respond_to do |format|
        format.html { redirect_back fallback_location: polymorphic_path([:business_manager, @attachable]), notice: 'Attachment updated successfully.' }
        format.json { render json: attachment_json(@job_attachment) }
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: polymorphic_path([:business_manager, @attachable]), alert: @job_attachment.errors.full_messages.join(', ') }
        format.json { render json: { errors: @job_attachment.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /manage/job_attachments/:id
  def destroy
    @job_attachment.destroy

    respond_to do |format|
      format.html { redirect_back fallback_location: polymorphic_path([:business_manager, @attachable]), notice: 'Attachment deleted successfully.' }
      format.json { head :no_content }
    end
  end

  # POST /manage/job_attachments/reorder
  def reorder
    if params[:attachment_ids].present?
      params[:attachment_ids].each_with_index do |id, index|
        attachment = @attachable.job_attachments.find_by(id: id)
        attachment&.update_column(:position, index)
      end
    end

    respond_to do |format|
      format.html { redirect_back fallback_location: polymorphic_path([:business_manager, @attachable]), notice: 'Attachments reordered successfully.' }
      format.json { render json: { success: true } }
    end
  end

  private

  def set_attachable
    if params[:service_id]
      @attachable = current_business.services.find(params[:service_id])
      @attachable_type = 'Service'
    elsif params[:estimate_id]
      @attachable = current_business.estimates.find(params[:estimate_id])
      @attachable_type = 'Estimate'
    elsif params[:booking_id]
      @attachable = current_business.bookings.find(params[:booking_id])
      @attachable_type = 'Booking'
    else
      redirect_to business_manager_dashboard_path, alert: 'Invalid attachment context.'
      return
    end
  end

  def set_job_attachment
    @job_attachment = @attachable.job_attachments.find(params[:id])
  end

  def job_attachment_params
    # Handle both nested (job_attachment[field]) and flat (field) parameter formats
    if params[:job_attachment].present?
      params.require(:job_attachment).permit(
        :attachment_type,
        :title,
        :description,
        :instructions,
        :visibility,
        :position,
        :file
      )
    else
      params.permit(
        :attachment_type,
        :title,
        :description,
        :instructions,
        :visibility,
        :position,
        :file
      )
    end
  end

  def attachment_json(attachment)
    {
      id: attachment.id,
      title: attachment.display_name,
      attachment_type: attachment.attachment_type,
      visibility: attachment.visibility,
      position: attachment.position,
      description: attachment.description,
      instructions: attachment.instructions,
      is_image: attachment.image?,
      is_pdf: attachment.pdf?,
      file_size: attachment.file_size_display,
      file_url: attachment.file.attached? ? rails_public_blob_url(attachment.file) : nil,
      thumbnail_url: attachment.image? && attachment.file.attached? ? rails_public_blob_url(attachment.file.variant(:thumb)) : nil,
      created_at: attachment.created_at.iso8601,
      uploaded_by: attachment.uploaded_by_user&.full_name
    }
  end

  def attachments_json(attachments)
    attachments.map { |a| attachment_json(a) }
  end
end

# frozen_string_literal: true

class BusinessManager::JobFormSubmissionsController < BusinessManager::BaseController
  before_action :set_job_form_submission, only: [:show, :approve, :request_revision]

  # GET /manage/job_form_submissions
  def index
    @job_form_submissions = current_business.job_form_submissions
                                            .includes(:booking, :job_form_template, :staff_member, :submitted_by_user)
                                            .recent

    # Filter by status
    if params[:status].present?
      @job_form_submissions = @job_form_submissions.where(status: params[:status])
    end

    # Filter by booking
    if params[:booking_id].present?
      @job_form_submissions = @job_form_submissions.for_booking(params[:booking_id])
    end

    # Filter by template
    if params[:template_id].present?
      @job_form_submissions = @job_form_submissions.for_template(params[:template_id])
    end

    # Filter by date range
    if params[:from_date].present?
      @job_form_submissions = @job_form_submissions.where('created_at >= ?', params[:from_date].to_date.beginning_of_day)
    end
    if params[:to_date].present?
      @job_form_submissions = @job_form_submissions.where('created_at <= ?', params[:to_date].to_date.end_of_day)
    end

    @job_form_submissions = @job_form_submissions.page(params[:page]) if @job_form_submissions.respond_to?(:page)

    # Summary stats for dashboard
    @pending_count = current_business.job_form_submissions.pending_review.count
    @completed_count = current_business.job_form_submissions.completed.count
  end

  # GET /manage/job_form_submissions/:id
  def show
    @booking = @job_form_submission.booking
    @template = @job_form_submission.job_form_template
    @responses_with_labels = @job_form_submission.responses_with_labels
  end

  # GET /manage/job_form_submissions/by_booking
  def by_booking
    @booking = current_business.bookings.find(params[:booking_id])
    @job_form_submissions = @booking.job_form_submissions
                                    .includes(:job_form_template, :submitted_by_user)
                                    .recent
  end

  # PATCH /manage/job_form_submissions/:id/approve
  def approve
    if @job_form_submission.approve!(user: current_user)
      respond_to do |format|
        format.html { redirect_to business_manager_job_form_submission_path(@job_form_submission), notice: 'Form submission approved.' }
        format.json { render json: { status: 'approved' } }
      end
    else
      respond_to do |format|
        format.html { redirect_to business_manager_job_form_submission_path(@job_form_submission), alert: 'Could not approve form submission.' }
        format.json { render json: { error: 'Could not approve' }, status: :unprocessable_entity }
      end
    end
  end

  # PATCH /manage/job_form_submissions/:id/request_revision
  def request_revision
    if @job_form_submission.request_revision!(user: current_user, notes: params[:notes])
      respond_to do |format|
        format.html { redirect_to business_manager_job_form_submission_path(@job_form_submission), notice: 'Revision requested.' }
        format.json { render json: { status: 'requires_revision' } }
      end
    else
      respond_to do |format|
        format.html { redirect_to business_manager_job_form_submission_path(@job_form_submission), alert: 'Could not request revision.' }
        format.json { render json: { error: 'Could not request revision' }, status: :unprocessable_entity }
      end
    end
  end

  private

  def set_job_form_submission
    @job_form_submission = current_business.job_form_submissions.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to business_manager_job_form_submissions_path, alert: 'Submission not found.'
  end
end

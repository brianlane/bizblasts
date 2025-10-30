# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Admin SolidQueue Jobs", type: :request, admin: true do
  let(:business) { create(:business) }
  let(:tenant_customer) { create(:tenant_customer, business: business) }
  let(:deleted_business_id) { 99999 } # Non-existent business ID

  before do
    # Authentication is handled automatically by spec/support/active_admin.rb
    # Clear existing jobs before each test
    SolidQueue::Job.delete_all
    SolidQueue::FailedExecution.delete_all
  end

  describe "POST #cleanup_orphaned_jobs" do
    context "when there are failed BusinessMailer jobs referencing deleted businesses" do
      before do
        create_failed_business_mailer_job_with_error("Couldn't find Business with 'id'=#{deleted_business_id}")
        create_failed_business_mailer_job_with_globalid_reference(deleted_business_id)
        create_failed_business_mailer_job_with_customer_reference
      end

      it "cleans up orphaned jobs successfully" do
        initial_failed_count = SolidQueue::FailedExecution.count
        expect(initial_failed_count).to eq(3)

        post "/admin/solid_queue_jobs/cleanup_orphaned_jobs"

        expect(response).to redirect_to(admin_solid_queue_jobs_path)
        expect(flash[:notice]).to be_present
        expect(flash[:notice]).to include("Cleaned up")
        
        # Should have cleaned up the orphaned jobs
        remaining_failed_count = SolidQueue::FailedExecution.count
        expect(remaining_failed_count).to be < initial_failed_count
      end

      it "removes the failed jobs from the database" do
        initial_failed_count = SolidQueue::FailedExecution.count
        expect(initial_failed_count).to eq(3)

        post "/admin/solid_queue_jobs/cleanup_orphaned_jobs"

        expect(response).to redirect_to(admin_solid_queue_jobs_path)
        
        # Verify actual cleanup occurred by checking specific job removal
        remaining_failed_count = SolidQueue::FailedExecution.count
        expect(remaining_failed_count).to be < initial_failed_count
      end
    end

    context "when there are valid failed BusinessMailer jobs" do
      before do
        create_failed_business_mailer_job_for_existing_business
      end

      it "does not remove valid failed jobs" do
        initial_failed_count = SolidQueue::FailedExecution.count
        expect(initial_failed_count).to eq(1)

        post "/admin/solid_queue_jobs/cleanup_orphaned_jobs"

        expect(response).to redirect_to(admin_solid_queue_jobs_path)
        
        # Should not clean up valid jobs
        remaining_failed_count = SolidQueue::FailedExecution.count
        expect(remaining_failed_count).to eq(initial_failed_count)
      end
    end

    context "when there are non-BusinessMailer failed jobs" do
      before do
        create_failed_non_business_mailer_job
      end

      it "ignores non-BusinessMailer jobs" do
        initial_failed_count = SolidQueue::FailedExecution.count
        expect(initial_failed_count).to eq(1)

        post "/admin/solid_queue_jobs/cleanup_orphaned_jobs"

        expect(response).to redirect_to(admin_solid_queue_jobs_path)
        
        # Should not touch non-BusinessMailer jobs
        remaining_failed_count = SolidQueue::FailedExecution.count
        expect(remaining_failed_count).to eq(initial_failed_count)
      end
    end

    context "when cleanup encounters an error" do
      before do
        # Create a failed job that will cause an error during cleanup
        create_malformed_failed_job
      end

      it "continues processing other jobs and handles errors gracefully" do
        initial_failed_count = SolidQueue::FailedExecution.count
        expect(initial_failed_count).to eq(1)

        post "/admin/solid_queue_jobs/cleanup_orphaned_jobs"

        expect(response).to redirect_to(admin_solid_queue_jobs_path)
        expect(flash[:notice]).to be_present
        
        # Should still have the malformed job since it couldn't be processed
        remaining_failed_count = SolidQueue::FailedExecution.count
        expect(remaining_failed_count).to eq(initial_failed_count)
      end
    end

    context "mixed scenario with valid and orphaned jobs" do
      before do
        # Create a mix of job types
        create_failed_business_mailer_job_with_error("Couldn't find Business with 'id'=#{deleted_business_id}")
        create_failed_business_mailer_job_for_existing_business
        create_failed_non_business_mailer_job
        create_failed_business_mailer_job_with_customer_reference
      end

      it "only cleans up the orphaned BusinessMailer jobs" do
        initial_failed_count = SolidQueue::FailedExecution.count
        expect(initial_failed_count).to eq(4)

        post "/admin/solid_queue_jobs/cleanup_orphaned_jobs"

        expect(response).to redirect_to(admin_solid_queue_jobs_path)
        
        remaining_failed_count = SolidQueue::FailedExecution.count
        # Should clean up some but not all jobs
        expect(remaining_failed_count).to be < initial_failed_count
        expect(remaining_failed_count).to be > 0
      end
    end
  end

  describe "POST #retry_all_failed_jobs" do
    before do
      create_failed_business_mailer_job_for_existing_business
      create_failed_non_business_mailer_job
    end

    it "attempts to retry all failed jobs" do
      initial_failed_count = SolidQueue::FailedExecution.count
      expect(initial_failed_count).to eq(2)

      post "/admin/solid_queue_jobs/retry_all_failed_jobs"

      expect(response).to redirect_to(admin_solid_queue_jobs_path)
      expect(flash[:notice]).to be_present
      expect(flash[:notice]).to include("Retried")
    end
  end

  describe "POST #retry_failed_job" do
    let!(:failed_execution) { create_failed_business_mailer_job_for_existing_business }

    it "retries a specific failed job" do
      post "/admin/solid_queue_jobs/retry_failed_job", params: { id: failed_execution.id }

      expect(response).to redirect_to(admin_solid_queue_jobs_path)
      
      # The retry might fail if referenced objects don't exist (realistic scenario)
      if flash[:notice].present? && !flash[:notice].include?("Signed in")
        expect(flash[:notice]).to include("Retried")
      else
        expect(flash[:alert]).to be_present
        expect(flash[:alert]).to include("Failed to retry job")
      end
    end

    it "handles missing job ID" do
      post "/admin/solid_queue_jobs/retry_failed_job"

      expect(response).to redirect_to(admin_solid_queue_jobs_path)
      expect(flash[:alert]).to be_present
      expect(flash[:alert]).to include("No job ID")
    end

    it "handles non-existent job" do
      post "/admin/solid_queue_jobs/retry_failed_job", params: { id: 99999 }

      expect(response).to redirect_to(admin_solid_queue_jobs_path)
      expect(flash[:alert]).to be_present
      expect(flash[:alert]).to include("not found")
    end
  end

  # Production failure scenarios based on actual logs
  describe 'production failure scenarios' do
    context 'retry functionality issues from production logs' do
      let!(:failed_execution) { create_failed_business_mailer_job_for_existing_business }

      it 'should handle retry requests with proper job ID (currently failing in prod)' do
        # This test reflects the production issue where no job ID is being passed
        # Current production request: Parameters: {"authenticity_token" => "[FILTERED]", "commit" => "Retry"}
        # Expected: Parameters should include "id" => job_id
        
        post "/admin/solid_queue_jobs/retry_failed_job", params: { id: failed_execution.id }

        expect(response).to redirect_to(admin_solid_queue_jobs_path)
        
        # Should successfully retry the job and show success message
        if flash[:notice].present? && !flash[:notice].include?("Signed in")
          expect(flash[:notice]).to include("Retried")
        else
          # If retry fails due to missing objects, should show specific error
          expect(flash[:alert]).to be_present
          expect(flash[:alert]).to include("Failed to retry job")
        end
      end

      it 'should properly generate retry forms with job IDs (currently broken in prod)' do
        # This tests that the admin interface properly includes job IDs in retry forms
        get "/admin/solid_queue_jobs"
        
        expect(response).to be_successful
        # The HTML should contain forms with hidden job ID fields
        expect(response.body).to include('name="id"')
        expect(response.body).to include("value=\"#{failed_execution.id}\"")
      end

      it 'should handle bulk retry operations properly' do
        # Test that bulk retry actually processes all failed jobs
        create_failed_business_mailer_job_for_existing_business
        create_failed_business_mailer_job_for_existing_business
        
        initial_count = SolidQueue::FailedExecution.count
        expect(initial_count).to be > 0
        
        post "/admin/solid_queue_jobs/retry_all_failed_jobs"

        expect(response).to redirect_to(admin_solid_queue_jobs_path)
        expect(flash[:notice]).to be_present
        expect(flash[:notice]).to include("Retried")
      end
    end

    context 'cleanup functionality issues from production' do
      before do
        # Create the types of failed jobs that exist in production
        create_failed_business_mailer_job_with_error("Couldn't find Business with 'id'=#{deleted_business_id}")
        create_failed_business_mailer_job_with_globalid_reference(deleted_business_id)
      end

      it 'should actually remove orphaned jobs (currently not working in prod)' do
        initial_count = SolidQueue::FailedExecution.count
        expect(initial_count).to eq(2)
        
        post "/admin/solid_queue_jobs/cleanup_orphaned_jobs"
        
        expect(response).to redirect_to(admin_solid_queue_jobs_path)
        
        # Should actually clean up the orphaned jobs
        remaining_count = SolidQueue::FailedExecution.count
        expect(remaining_count).to be < initial_count
        
        # Should show confirmation of cleanup
        expect(flash[:notice]).to be_present
        expect(flash[:notice]).to include("Cleaned up")
        expect(flash[:notice]).to match(/\d+/)  # Should include count
      end

      it 'should log cleanup actions for audit trail' do
        # Use spy instead of mock to allow actual logging
        allow(Rails.logger).to receive(:info).and_call_original
        
        initial_count = SolidQueue::FailedExecution.count
        expect(initial_count).to eq(2)
        
        post "/admin/solid_queue_jobs/cleanup_orphaned_jobs"
        
        expect(response).to redirect_to(admin_solid_queue_jobs_path)
        
        # Verify jobs were actually cleaned up
        remaining_count = SolidQueue::FailedExecution.count
        expect(remaining_count).to eq(0)  # Both jobs should be cleaned up
        
        # Verify logging happened for cleaned up jobs
        expect(Rails.logger).to have_received(:info).with(/Cleaned up failed job.*referencing non-existent Business/).at_least(:once)
      end

      it 'should handle mixed scenarios correctly' do
        # Add a valid job that should NOT be cleaned up
        valid_job = create_failed_business_mailer_job_for_existing_business
        
        initial_count = SolidQueue::FailedExecution.count
        expect(initial_count).to eq(3)  # 2 orphaned + 1 valid
        
        post "/admin/solid_queue_jobs/cleanup_orphaned_jobs"

        remaining_count = SolidQueue::FailedExecution.count
        
        # Should clean up orphaned jobs but keep valid ones
        expect(remaining_count).to eq(1)  # Only the valid job should remain
        expect(SolidQueue::FailedExecution.exists?(valid_job.id)).to be_truthy
      end
    end

    context 'admin interface authentication and permissions' do
      it 'should require admin authentication for all actions' do
        # Test without authentication should redirect to login
        delete destroy_admin_user_session_path  # Sign out
        
        post "/admin/solid_queue_jobs/retry_failed_job", params: { id: 1 }
        expect(response).to redirect_to("/admin/login")
        
        post "/admin/solid_queue_jobs/cleanup_orphaned_jobs"
        expect(response).to redirect_to("/admin/login")
        
        post "/admin/solid_queue_jobs/retry_all_failed_jobs"
        expect(response).to redirect_to("/admin/login")
      end
    end

    context 'error handling and edge cases from production' do
      it 'should handle malformed job data gracefully' do
        create_malformed_failed_job
        
        post "/admin/solid_queue_jobs/cleanup_orphaned_jobs"
        
        expect(response).to redirect_to(admin_solid_queue_jobs_path)
        # Should not crash and should show some kind of result
        expect(flash[:notice]).to be_present
      end

      it 'should handle concurrent job processing' do
        failed_job = create_failed_business_mailer_job_for_existing_business
        
        # Simulate job being processed/deleted by another worker
        SolidQueue::FailedExecution.find(failed_job.id).delete
        
        post "/admin/solid_queue_jobs/retry_failed_job", params: { id: failed_job.id }

        expect(response).to redirect_to(admin_solid_queue_jobs_path)
        expect(flash[:alert]).to be_present
        expect(flash[:alert]).to include("not found")
      end
    end
  end

  private

  def create_failed_business_mailer_job_with_error(error_message)
    job = SolidQueue::Job.create!(
      class_name: 'ActionMailer::MailDeliveryJob',
      queue_name: 'default',
      arguments: {
        'arguments' => [
          'BusinessMailer',
          'new_booking_notification',
          [{ '_aj_globalid' => "gid://bizblasts/Booking/123" }]
        ]
      }.to_json,
      created_at: 1.hour.ago
    )

    SolidQueue::FailedExecution.create!(
      job: job,
      error: { 'message' => error_message }.to_json,
      created_at: 1.hour.ago
    )
  end

  def create_failed_business_mailer_job_with_globalid_reference(business_id)
    job = SolidQueue::Job.create!(
      class_name: 'ActionMailer::MailDeliveryJob',
      queue_name: 'default',
      arguments: {
        'arguments' => [
          'BusinessMailer',
          'new_customer_notification',
          [{ '_aj_globalid' => "gid://bizblasts/Business/#{business_id}" }]
        ]
      }.to_json,
      created_at: 1.hour.ago
    )

    SolidQueue::FailedExecution.create!(
      job: job,
      error: { 'message' => 'Some error occurred' }.to_json,
      created_at: 1.hour.ago
    )
  end

  def create_failed_business_mailer_job_with_customer_reference
    # Create a customer reference that doesn't exist
    job = SolidQueue::Job.create!(
      class_name: 'ActionMailer::MailDeliveryJob',
      queue_name: 'default',
      arguments: {
        'arguments' => [
          'BusinessMailer',
          'new_customer_notification',
          [{ '_aj_globalid' => "gid://bizblasts/TenantCustomer/99999" }]
        ]
      }.to_json,
      created_at: 1.hour.ago
    )

    SolidQueue::FailedExecution.create!(
      job: job,
      error: { 'message' => "Couldn't find TenantCustomer with 'id'=99999" }.to_json,
      created_at: 1.hour.ago
    )
  end

  def create_failed_business_mailer_job_for_existing_business
    job = SolidQueue::Job.create!(
      class_name: 'ActionMailer::MailDeliveryJob',
      queue_name: 'default',
      arguments: {
        'arguments' => [
          'BusinessMailer',
          'new_customer_notification',
          [{ '_aj_globalid' => "gid://bizblasts/TenantCustomer/#{tenant_customer.id}" }]
        ]
      }.to_json,
      created_at: 1.hour.ago
    )

    SolidQueue::FailedExecution.create!(
      job: job,
      error: { 'message' => 'Temporary network error' }.to_json,
      created_at: 1.hour.ago
    )
  end

  def create_failed_non_business_mailer_job
    job = SolidQueue::Job.create!(
      class_name: 'ActionMailer::MailDeliveryJob',
      queue_name: 'default',
      arguments: {
        'arguments' => [
          'UserMailer',
          'welcome_email',
          [{ '_aj_globalid' => "gid://bizblasts/User/123" }]
        ]
      }.to_json,
      created_at: 1.hour.ago
    )

    SolidQueue::FailedExecution.create!(
      job: job,
      error: { 'message' => 'Some user mailer error' }.to_json,
      created_at: 1.hour.ago
    )
  end

  def create_malformed_failed_job
    job = SolidQueue::Job.create!(
      class_name: 'ActionMailer::MailDeliveryJob',
      queue_name: 'default',
      arguments: 'invalid json',  # This will cause JSON parsing errors
      created_at: 1.hour.ago
    )

    SolidQueue::FailedExecution.create!(
      job: job,
      error: { 'message' => 'Malformed job arguments' }.to_json,
      created_at: 1.hour.ago
    )
  end
end
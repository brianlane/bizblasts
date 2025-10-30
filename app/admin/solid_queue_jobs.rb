# frozen_string_literal: true

ActiveAdmin.register_page "Solid Queue Jobs" do
  menu parent: "System", label: "Background Jobs", priority: 2

  content title: "Background Job Monitoring" do
    div class: "dashboard-section" do
      h3 "Job Statistics"
      
      div class: "stats-grid", style: "display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px;" do
        div class: "stat-card", style: "background: #f8f9fa; padding: 20px; border-radius: 8px; text-align: center;" do
          h4 "Total Jobs", style: "margin: 0 0 10px 0; color: #666;"
          div SolidQueue::Job.count.to_s, style: "font-size: 2em; font-weight: bold; color: #2c3e50;"
        end
        
        div class: "stat-card", style: "background: #fff3cd; padding: 20px; border-radius: 8px; text-align: center;" do
          h4 "Ready Jobs", style: "margin: 0 0 10px 0; color: #666;"
          div SolidQueue::ReadyExecution.count.to_s, style: "font-size: 2em; font-weight: bold; color: #856404;"
        end
        
        div class: "stat-card", style: "background: #f8d7da; padding: 20px; border-radius: 8px; text-align: center;" do
          h4 "Failed Jobs", style: "margin: 0 0 10px 0; color: #666;"
          div SolidQueue::FailedExecution.count.to_s, style: "font-size: 2em; font-weight: bold; color: #721c24;"
        end
        
        div class: "stat-card", style: "background: #d1ecf1; padding: 20px; border-radius: 8px; text-align: center;" do
          h4 "Email Jobs", style: "margin: 0 0 10px 0; color: #666;"
          div SolidQueue::Job.where(class_name: 'ActionMailer::MailDeliveryJob').count.to_s, style: "font-size: 2em; font-weight: bold; color: #0c5460;"
        end
      end
    end

    div class: "dashboard-section" do
      h3 "Recent Jobs (Last 10)"
      
      table_for SolidQueue::Job.order(created_at: :desc).limit(10), class: "index_table" do
        column "Created" do |job|
          time_ago_in_words(job.created_at) + " ago"
        end
        column "Class" do |job|
          job.class_name
        end
        column "Queue" do |job|
          job.queue_name
        end
        column "Status" do |job|
          if job.finished_at.present?
            status_tag("Completed")
          elsif SolidQueue::FailedExecution.exists?(job_id: job.id)
            status_tag("Failed")
          elsif SolidQueue::ReadyExecution.exists?(job_id: job.id)
            status_tag("Ready")
          else
            status_tag("Processing")
          end
        end
        column "Finished" do |job|
          job.finished_at ? time_ago_in_words(job.finished_at) + " ago" : "-"
        end
      end
    end

    if SolidQueue::FailedExecution.count > 0
      div class: "dashboard-section" do
        h3 "Failed Jobs", style: "color: #721c24;"
        
        div style: "margin-bottom: 15px;" do
          form_tag admin_solid_queue_jobs_retry_all_failed_jobs_path, method: :post,
                   onsubmit: "return confirm('Are you sure you want to retry all failed jobs?')",
                   style: "display: inline-block; margin-right: 10px;" do
            submit_tag "Retry All Failed Jobs",
                       class: "button",
                       style: "background-color: #dc3545; color: white; border: none; padding: 8px 16px; cursor: pointer;"
          end

          form_tag admin_solid_queue_jobs_cleanup_orphaned_jobs_path, method: :post,
                   onsubmit: "return confirm('This will permanently discard failed jobs that reference deleted businesses. Continue?')",
                   style: "display: inline-block;" do
            submit_tag "Clean Up Orphaned Jobs",
                       class: "button",
                       style: "background-color: #6c757d; color: white; border: none; padding: 8px 16px; cursor: pointer;"
          end
        end
        
        table_for SolidQueue::FailedExecution.joins(:job).order('solid_queue_jobs.created_at DESC').limit(10), class: "index_table" do
          column "Job Class" do |failed_execution|
            failed_execution.job.class_name
          end
          column "Failed At" do |failed_execution|
            time_ago_in_words(failed_execution.created_at) + " ago"
          end
          column "Error" do |failed_execution|
            truncate(failed_execution.error.is_a?(Hash) ? failed_execution.error['message'] : failed_execution.error.to_s, length: 100)
          end
          column "Actions" do |failed_execution|
            raw <<~HTML
              <form style="display: inline;" action="#{admin_solid_queue_jobs_retry_failed_job_path}" method="post">
                <input type="hidden" name="authenticity_token" value="#{form_authenticity_token}">
                <input type="hidden" name="id" value="#{failed_execution.id}">
                <input type="submit" name="commit" value="Retry" class="button"
                       style="background-color: #28a745; color: white; font-size: 12px; padding: 5px 10px; border: none; cursor: pointer;">
              </form>
            HTML
          end
        end
      end
    end

    div class: "dashboard-section" do
      h3 "Email Job Monitoring"
      
      email_jobs = SolidQueue::Job.where(class_name: 'ActionMailer::MailDeliveryJob').order(created_at: :desc).limit(10)
      
      if email_jobs.any?
        table_for email_jobs, class: "index_table" do
          column "Created" do |job|
            time_ago_in_words(job.created_at) + " ago"
          end
          column "Mailer" do |job|
            begin
              args = JSON.parse(job.arguments)
              args.dig('arguments', 0) || 'Unknown'
            rescue
              'Unknown'
            end
          end
          column "Method" do |job|
            begin
              args = JSON.parse(job.arguments)
              args.dig('arguments', 1) || 'Unknown'
            rescue
              'Unknown'
            end
          end
          column "Status" do |job|
            if job.finished_at.present?
              status_tag("Sent")
            elsif SolidQueue::FailedExecution.exists?(job_id: job.id)
              status_tag("Failed")
            elsif SolidQueue::ReadyExecution.exists?(job_id: job.id)
              status_tag("Queued")
            else
              status_tag("Sending")
            end
          end
          column "Finished" do |job|
            job.finished_at ? time_ago_in_words(job.finished_at) + " ago" : "-"
          end
        end
      else
        div "No email jobs found.", style: "color: #666; font-style: italic;"
      end
    end
  end

  # Custom controller actions - defined as instance methods to avoid Rails 8.1 deprecation warnings
  # with page_action. These are called from custom routes in routes.rb
  controller do
    def retry_all_failed_jobs
      retried_count = 0
      failed_count = 0

      SolidQueue::FailedExecution.find_each do |failed_execution|
        begin
          failed_execution.retry
          retried_count += 1
        rescue => e
          Rails.logger.error "[SolidQueue] Failed to retry job #{failed_execution.id}: #{e.message}"
          failed_count += 1
          # Continue with other jobs even if one fails
        end
      end

      if failed_count > 0
        redirect_to admin_solid_queue_jobs_path, notice: "Retried #{retried_count} jobs successfully. #{failed_count} jobs could not be retried (check logs for details)."
      else
        redirect_to admin_solid_queue_jobs_path, notice: "Retried #{retried_count} failed jobs."
      end
    end

    def retry_failed_job
      if params[:id].blank?
        redirect_to admin_solid_queue_jobs_path, alert: "No job ID provided for retry."
        return
      end

      begin
        failed_execution = SolidQueue::FailedExecution.find(params[:id])
        failed_execution.retry
        redirect_to admin_solid_queue_jobs_path, notice: "Retried failed job successfully."
      rescue ActiveRecord::RecordNotFound
        redirect_to admin_solid_queue_jobs_path, alert: "Failed job not found (may have already been processed)."
      rescue => e
        Rails.logger.error "[SolidQueue] Failed to retry job #{params[:id]}: #{e.message}"
        redirect_to admin_solid_queue_jobs_path, alert: "Failed to retry job: #{e.message}"
      end
    end

    def cleanup_orphaned_jobs
      cleaned_count = 0

      # Find failed jobs that reference non-existent businesses
      SolidQueue::FailedExecution.joins(:job).find_each do |failed_execution|
        begin
          # Handle both string and already-parsed arguments
          job_args = if failed_execution.job.arguments.is_a?(String)
                       JSON.parse(failed_execution.job.arguments)
                     else
                       failed_execution.job.arguments
                     end

          # Check if this is a mailer job that might reference a business
          if failed_execution.job.class_name == 'ActionMailer::MailDeliveryJob'
            mailer_class = job_args.dig('arguments', 0)

            if mailer_class == 'BusinessMailer'
              # Try to find the business referenced in the job
              mailer_args = job_args.dig('arguments', 2)
              business_id = nil
              should_discard = false

              # Handle different argument structures for different mailer methods
              case mailer_args
              when Hash
                business_id = mailer_args['business_id'] if mailer_args.key?('business_id')
              when Array
                # Extract business ID from various ActiveRecord objects
                mailer_args.each do |arg|
                  if arg.is_a?(Hash) && arg['_aj_globalid']
                    gid = arg['_aj_globalid']

                    if gid.include?('Business/')
                      business_id = gid.split('/').last.to_i
                      break
                    elsif gid.include?('TenantCustomer/') || gid.include?('Order/') || gid.include?('Payment/') || gid.include?('Booking/')
                      # These objects have business associations - check if the referenced object exists
                      begin
                        object_class = gid.split('/')[1]
                        object_id = gid.split('/').last.to_i

                        case object_class
                        when 'TenantCustomer'
                          customer = TenantCustomer.find(object_id)
                          business_id = customer.business_id
                        when 'Order'
                          order = Order.find(object_id)
                          business_id = order.business_id
                        when 'Payment'
                          payment = Payment.find(object_id)
                          business_id = payment.business_id
                        when 'Booking'
                          booking = Booking.find(object_id)
                          business_id = booking.business_id
                        end
                      rescue ActiveRecord::RecordNotFound
                        # If the referenced object doesn't exist, discard the job
                        should_discard = true
                        break
                      end
                    end
                  end
                end
              end

              # Also check the error message for business ID references
              if business_id.nil?
                error_text = if failed_execution.error.is_a?(String)
                              failed_execution.error
                            elsif failed_execution.error.is_a?(Hash)
                              failed_execution.error['message'] || failed_execution.error['error'] || failed_execution.error.to_s
                            else
                              failed_execution.error.to_s
                            end

                if error_text && (match = error_text.match(/Couldn't find Business with 'id'=(\d+)/))
                  business_id = match[1].to_i
                end
              end

              # If we can identify a business ID and it doesn't exist, discard the job
              if should_discard || (business_id && !Business.exists?(business_id))
                failed_execution.discard
                cleaned_count += 1
                Rails.logger.info "[SolidQueue] Cleaned up failed job #{failed_execution.id} referencing non-existent Business #{business_id}"
              end
            end
          end
        rescue => e
          Rails.logger.error "[SolidQueue] Error checking job #{failed_execution.id}: #{e.message}"
          # Continue with other jobs
        end
      end

      redirect_to admin_solid_queue_jobs_path, notice: "Cleaned up #{cleaned_count} orphaned failed jobs."
    end
  end
end 
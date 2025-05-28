# frozen_string_literal: true

ActiveAdmin.register_page "SolidQueue Jobs" do
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
          link_to "Retry All Failed Jobs", 
                  admin_solidqueue_jobs_retry_all_failed_jobs_path, 
                  method: :post, 
                  class: "button", 
                  style: "background-color: #dc3545; color: white;",
                  confirm: "Are you sure you want to retry all failed jobs?"
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
            link_to "Retry", 
                    admin_solidqueue_jobs_retry_failed_job_path(failed_execution.id), 
                    method: :post, 
                    class: "button",
                    style: "background-color: #28a745; color: white; font-size: 12px; padding: 5px 10px;"
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

  page_action :retry_all_failed_jobs, method: :post do
    retried_count = 0
    SolidQueue::FailedExecution.find_each do |failed_execution|
      failed_execution.retry
      retried_count += 1
    end
    
    redirect_to admin_solidqueue_jobs_path, notice: "Retried #{retried_count} failed jobs."
  end

  page_action :retry_failed_job, method: :post do
    failed_execution = SolidQueue::FailedExecution.find(params[:id])
    failed_execution.retry
    
    redirect_to admin_solidqueue_jobs_path, notice: "Retried failed job."
  end
end 
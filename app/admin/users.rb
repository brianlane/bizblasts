ActiveAdmin.register User do
  permit_params :email, :first_name, :last_name, :role, :business_id, :active, :password, :password_confirmation, :staff_member_id, :phone

  # Filters
  filter :email
  filter :first_name
  filter :last_name
  filter :role, as: :select, collection: User.roles.keys.map { |r| [r.humanize, r] }
  filter :business, as: :select, collection: -> { Business.order(:name).pluck(:name, :id) }
  filter :active
  filter :created_at
  filter :last_sign_in_at
  filter :sign_in_count

  # Enable batch actions
  batch_action :destroy, confirm: "Are you sure you want to delete these users?" do |ids|
    deleted_count = 0
    failed_count = 0
    
    User.where(id: ids).find_each do |user|
      begin
        user.destroy!
        deleted_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to delete user #{user.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{deleted_count} users deleted successfully. #{failed_count} users failed to delete."
    else
      redirect_to collection_path, notice: "#{deleted_count} users deleted successfully."
    end
  end

  batch_action :activate, confirm: "Are you sure you want to activate these users?" do |ids|
    updated_count = 0
    failed_count = 0
    
    User.where(id: ids).find_each do |user|
      begin
        # Assuming users have an active field or similar
        user.update!(confirmed_at: Time.current) if user.confirmed_at.nil?
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to activate user #{user.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} users activated successfully. #{failed_count} users failed to activate."
    else
      redirect_to collection_path, notice: "#{updated_count} users activated successfully."
    end
  end

  batch_action :deactivate, confirm: "Are you sure you want to deactivate these users?" do |ids|
    updated_count = 0
    failed_count = 0
    
    User.where(id: ids).find_each do |user|
      begin
        # Deactivate by removing confirmation
        user.update!(confirmed_at: nil)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to deactivate user #{user.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} users deactivated successfully. #{failed_count} users failed to deactivate."
    else
      redirect_to collection_path, notice: "#{updated_count} users deactivated successfully."
    end
  end

  # Index Page Configuration
  index do
    # Daily Active Users panel at the top
    panel "Daily Active Users Analytics" do
      div class: "dau-analytics" do
        # Get analytics data
        today_dau = DailyActiveUsersService.today
        yesterday_dau = DailyActiveUsersService.yesterday
        weekly_dau = DailyActiveUsersService.weekly_active_users
        monthly_dau = DailyActiveUsersService.monthly_active_users
        engagement_metrics = DailyActiveUsersService.engagement_metrics
        
        # Create a responsive grid layout
        div class: "analytics-grid", style: "display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-bottom: 20px;" do
          # Today's DAU
          div class: "metric-card", style: "background: #f8f9fa; padding: 15px; border-radius: 8px; text-align: center;" do
            h4 "Today's Active Users", style: "margin: 0 0 10px 0; color: #495057;"
            h2 today_dau.to_s, style: "margin: 0; color: #007bff; font-size: 2em;"
            small "#{yesterday_dau > 0 ? ((today_dau - yesterday_dau).to_f / yesterday_dau * 100).round(1) : 0}% vs yesterday", 
                  style: "color: #{today_dau >= yesterday_dau ? '#28a745' : '#dc3545'};"
          end
          
          # Weekly DAU
          div class: "metric-card", style: "background: #f8f9fa; padding: 15px; border-radius: 8px; text-align: center;" do
            h4 "Weekly Active Users", style: "margin: 0 0 10px 0; color: #495057;"
            h2 weekly_dau.to_s, style: "margin: 0; color: #28a745; font-size: 2em;"
            small "Last 7 days", style: "color: #6c757d;"
          end
          
          # Monthly DAU
          div class: "metric-card", style: "background: #f8f9fa; padding: 15px; border-radius: 8px; text-align: center;" do
            h4 "Monthly Active Users", style: "margin: 0 0 10px 0; color: #495057;"
            h2 monthly_dau.to_s, style: "margin: 0; color: #ffc107; font-size: 2em;"
            small "Last 30 days", style: "color: #6c757d;"
          end
          
          # Engagement Rate
          div class: "metric-card", style: "background: #f8f9fa; padding: 15px; border-radius: 8px; text-align: center;" do
            h4 "Daily Engagement Rate", style: "margin: 0 0 10px 0; color: #495057;"
            h2 "#{engagement_metrics[:daily_engagement_rate]}%", style: "margin: 0; color: #6f42c1; font-size: 2em;"
            small "Active users / Total users", style: "color: #6c757d;"
          end
        end
        
        # Activity breakdown by role
        role_breakdown = DailyActiveUsersService.activity_by_role
        if role_breakdown.any?
          div class: "role-breakdown", style: "margin-top: 15px;" do
            h4 "Activity by Role (Last 30 days)", style: "margin-bottom: 10px;"
            table style: "width: 100%; border-collapse: collapse;" do
              thead do
                tr do
                  th "Role", style: "text-align: left; padding: 8px; border-bottom: 1px solid #dee2e6;"
                  th "Active Users", style: "text-align: right; padding: 8px; border-bottom: 1px solid #dee2e6;"
                end
              end
              tbody do
                role_breakdown.each do |role, count|
                  tr do
                    td role.humanize, style: "padding: 8px; border-bottom: 1px solid #f8f9fa;"
                    td count.to_s, style: "text-align: right; padding: 8px; border-bottom: 1px solid #f8f9fa;"
                  end
                end
              end
            end
          end
        end
      end
    end
    
    selectable_column
    id_column
    column :email
    column "Name", :full_name
    column :role do |user|
      user.role&.humanize
    end
    column :business do |user|
      if user.business&.id
        link_to user.business.name, admin_business_path(user.business.id)
      elsif user.business
        user.business.name || "Invalid Business"
      else
        "None"
      end
    end
    column "Staff Member" do |user|
      if user.business && user.staff_member
        link_to(user.staff_member.name, admin_staff_member_path(user.staff_member))
      else
        "N/A"
      end
    end
    column "Position" do |user|
      user.staff_member&.position
    end
    column "Last Login" do |user|
      if user.last_sign_in_at
        div do
          div time_ago_in_words(user.last_sign_in_at) + " ago"
          small user.last_sign_in_at.strftime("%b %d, %Y at %I:%M %p"), style: "color: #6c757d; font-size: 0.85em;"
        end
      else
        "Never"
      end
    end
    column "Sign-in Count" do |user|
      user.sign_in_count
    end
    column :active
    column :confirmed_at
    column :created_at
    actions
  end

  # Show Page Configuration
  show do
    attributes_table do
      row :id
      row :email
      row :full_name
      row :role do |user|
        user.role&.humanize
      end
      row :business if resource.requires_business?
      
      if resource.client?
        row :associated_businesses do |user|
          user.businesses.map do |b|
            if b&.id
              link_to(b.name, admin_business_path(b.id))
            else
              b&.name || "Invalid Business Record"
            end
          end.join(", ").html_safe
        end
      end
      
      row :staff_member do |user|
        if user.business && user.staff_member
          link_to(user.staff_member.name, admin_staff_member_path(user.staff_member))
        else
          "None"
        end
      end
      
      # Login Activity Section
      row :last_sign_in_at do |user|
        if user.last_sign_in_at
          "#{time_ago_in_words(user.last_sign_in_at)} ago (#{user.last_sign_in_at.strftime('%B %d, %Y at %I:%M %p')})"
        else
          "Never logged in"
        end
      end
      row :current_sign_in_at do |user|
        if user.current_sign_in_at
          "#{time_ago_in_words(user.current_sign_in_at)} ago (#{user.current_sign_in_at.strftime('%B %d, %Y at %I:%M %p')})"
        else
          "No current session"
        end
      end
      row :sign_in_count
      row :last_sign_in_ip
      row :current_sign_in_ip
      
      row :active
      row :confirmed_at
      row :created_at
      row :updated_at
      row :reset_password_sent_at
      row :remember_created_at
    end
    
    # Add a panel showing user's login activity timeline
    panel "Login Activity Timeline" do
      if resource.last_sign_in_at
        div class: "login-timeline" do
          h4 "Recent Login Activity"
          
          table do
            thead do
              tr do
                th "Metric"
                th "Value"
              end
            end
            tbody do
              tr do
                td "Total Sign-ins"
                td resource.sign_in_count
              end
              tr do
                td "Last Login"
                td resource.last_sign_in_at ? "#{time_ago_in_words(resource.last_sign_in_at)} ago" : "Never"
              end
              tr do
                td "Previous Login"
                td resource.current_sign_in_at ? "#{time_ago_in_words(resource.current_sign_in_at)} ago" : "N/A"
              end
              tr do
                td "Account Created"
                td "#{time_ago_in_words(resource.created_at)} ago"
              end
              if resource.last_sign_in_at && resource.created_at
                days_since_creation = (resource.last_sign_in_at.to_date - resource.created_at.to_date).to_i
                login_frequency = days_since_creation > 0 ? (resource.sign_in_count.to_f / days_since_creation).round(2) : 0
                tr do
                  td "Average Logins per Day"
                  td "#{login_frequency} times"
                end
              end
            end
          end
        end
      else
        para "User has never logged in."
      end
    end
    
    active_admin_comments
  end

  # Form Configuration
  form do |f|
    f.semantic_errors
    f.inputs "User Details" do
      f.input :role, as: :select, collection: User.roles.keys.map { |r| [r.humanize, r] }, input_html: { id: 'user_role_selector' }
      
      f.input :business, as: :select, collection: Business.order(:name).all, 
              wrapper_html: { class: ('input-hidden' unless f.object.requires_business?), id: 'user_business_input' }
              
      f.input :email
      f.input :first_name
      f.input :last_name
      f.input :phone
      
      f.input :staff_member, as: :select, 
              collection: StaffMember.where(business_id: f.object.business_id).order(:name).all,
              wrapper_html: { class: ('input-hidden' unless f.object.requires_business?), id: 'user_staff_member_input' }
              
      f.input :active
      
      if f.object.new_record?
        f.input :password
        f.input :password_confirmation
      end
    end
    f.actions
    
    script do
      raw <<-JS
        document.addEventListener('DOMContentLoaded', function() {
          var roleSelector = document.getElementById('user_role_selector');
          var businessInput = document.getElementById('user_business_input');
          var staffInput = document.getElementById('user_staff_member_input');
          
          function toggleBusinessFields() {
            var selectedRole = roleSelector.value;
            var requiresBusiness = (selectedRole === 'manager' || selectedRole === 'staff');
            
            if (businessInput) {
              businessInput.classList.toggle('input-hidden', !requiresBusiness);
            }
            if (staffInput) {
              staffInput.classList.toggle('input-hidden', !requiresBusiness);
            }
          }
          
          if (roleSelector) {
            roleSelector.addEventListener('change', toggleBusinessFields);
            toggleBusinessFields();
          }
        });
      JS
    end
  end
end

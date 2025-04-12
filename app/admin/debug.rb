require 'ostruct' # Required for OpenStruct
# frozen_string_literal: true

ActiveAdmin.register_page "Debug" do
  menu priority: 100, label: "Multi-Tenant Debug Information"

  # Moved action_item to the correct scope
  action_item :go_home do
    link_to "Back to Homepage", "/"
  end

  controller do
    # Skip authentication for this specific page if needed (ensure security implications are understood)
    # skip_before_action :authenticate_admin_user! 

    # Ensure tenant context is available if applicable, but don't rely on it being set by default AA filter
    # The main set_tenant filter in ApplicationController should handle hostname lookup
    
    def index
      # Explicitly find the tenant based on hostname, unscoped
      ActsAsTenant.without_tenant do 
        @current_tenant_in_action = Business.find_by(hostname: request.subdomain)
      end
      
      # Log the tenant status found within the action (Keep this specific log for now)
      Rails.logger.info "[Admin Debug - Action] Tenant in action: #{@current_tenant_in_action&.name || 'None'} for hostname: #{request.subdomain}"

      # Gather request info
      @request_info = {
        host: request.host,
        subdomain: request.subdomain,
        domain: request.domain,
        port: request.port,
        protocol: request.protocol,
        remote_ip: request.remote_ip,
        user_agent: request.user_agent
      }
      
      # Fetch all tenants for display, unscoped
      ActsAsTenant.without_tenant do
        @available_tenants = Business.order(:name).all
        # Removed count log
      end
    end
  end

  content title: "Multi-Tenant Debug Information" do
    # Access instance variables via controller object
    request_info = controller.instance_variable_get(:@request_info) || {}
    available_tenants = controller.instance_variable_get(:@available_tenants) || []
    current_tenant_action = controller.instance_variable_get(:@current_tenant_in_action)

    # Removed view count log

    # Try fetching tenant directly in view for comparison (may still be nil)
    # current_tenant_view = Business.current 
    # Rails.logger.info "[Admin Debug - View] Tenant in view (Business.current): #{current_tenant_view&.name || 'None'}"

    panel "Current Request Info" do
      attributes_table_for request_info do
        row :host
        row :subdomain
        row :domain
        row :port
        row :protocol
        row :remote_ip
        row :user_agent
      end
      
      # Simplified Tenant Display to match test expectations
      div do
        strong "Current Tenant: " # Match test expectation
        if current_tenant_action
          span current_tenant_action.name
        else
          span "None"
        end
      end
    end

    panel "Available Tenants" do
      # Removed view count log
      if available_tenants.any?
        table_for available_tenants.sort_by(&:name) do
          column :id
          column :name
          column :hostname do |tenant|
            tenant.hostname
          end
          column :tier
          column :active
          column "Test Links" do |tenant|
            hostname_with_domain = "#{tenant.hostname}.example.com" # Adjust domain as needed
            ul do
              li link_to "Visit Tenant Root", "http://#{hostname_with_domain}/", target: "_blank"
              li link_to "Client Login", "http://#{hostname_with_domain}/client/login", target: "_blank"
            end
          end
        end
      else
        para "No tenants found in the database."
      end
    end

    # Informational panels
    div class: "tenant-debug" do
      columns do
        column do
          panel "Multi-Tenancy Information" do
            para "This application uses ", strong("acts_as_tenant"), " for multi-tenancy."
            para "Data is separated through row-level tenant scoping rather than schema-level separation."
          end
        end
        column do
          panel "Test Your Tenants" do
            para "Use one of these methods to test multi-tenancy on localhost:"
            ul do
              li do
                strong "lvh.me: "
                text_node "Visit "
                a "http://lvh.me:#{request_info[:port]}", href: "http://lvh.me:#{request_info[:port]}", target: "_blank", rel: "noopener noreferrer"
                text_node " for public tenant, or "
                a "http://[subdomain].lvh.me:#{request_info[:port]}", href: "#", target: "_blank", rel: "noopener noreferrer"
                text_node " for specific tenant"
              end
              li do
                strong "127.0.0.1.xip.io: "
                text_node "Visit "
                a "http://127.0.0.1.xip.io:#{request_info[:port]}", href: "http://127.0.0.1.xip.io:#{request_info[:port]}", target: "_blank", rel: "noopener noreferrer"
                text_node " for public tenant, or "
                a "http://[subdomain].127.0.0.1.xip.io:#{request_info[:port]}", href: "#", target: "_blank", rel: "noopener noreferrer"
                text_node " for specific tenant"
              end
            end
          end
        end
      end
    end
  end
end 
# frozen_string_literal: true

class PolicyAcceptancesController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :check_policy_acceptance, only: [:status, :create, :bulk_create]
  
  def status
    missing_policies = current_user.missing_required_policies
    
    render json: {
      requires_policy_acceptance: current_user.needs_policy_acceptance?,
      missing_policies: missing_policies.map do |policy_type|
        version = PolicyVersion.current_version(policy_type)
        {
          policy_type: policy_type,
          policy_name: version&.policy_name || policy_type.humanize,
          policy_path: version&.policy_path || "/#{policy_type}",
          version: version&.version
        }
      end
    }
  end
  
  def show
    # Show the policy acceptance page (fallback for when modal fails)
  end
  
  def create
    policy_type = params[:policy_type]
    version = params[:version]
    
    current_version = PolicyVersion.current_version(policy_type)
    
    unless current_version && current_version.version == version
      render json: { success: false, error: 'Invalid policy version' }
      return
    end
    
    begin
      PolicyAcceptance.record_acceptance(current_user, policy_type, version, request)
      
      # Check if all required policies are now accepted
      if current_user.missing_required_policies.empty?
        current_user.mark_policies_accepted!
      end
      
      render json: { success: true }
    rescue => e
      Rails.logger.error "Policy acceptance error: #{e.message}"
      render json: { success: false, error: 'Failed to record acceptance' }
    end
  end
  
  def bulk_create
    policy_acceptances = params[:policy_acceptances] || {}
    errors = []
    
    ActiveRecord::Base.transaction do
      policy_acceptances.each do |policy_type, accepted|
        next unless accepted == '1'
        
        current_version = PolicyVersion.current_version(policy_type)
        unless current_version
          errors << "No current version for #{policy_type}"
          next
        end
        
        PolicyAcceptance.record_acceptance(current_user, policy_type, current_version.version, request)
      end
      
      # Check if all required policies are now accepted
      if current_user.missing_required_policies.empty?
        current_user.mark_policies_accepted!
      end
    end
    
    if errors.empty?
      render json: { success: true }
    else
      render json: { success: false, errors: errors }
    end
  rescue => e
    Rails.logger.error "Bulk policy acceptance error: #{e.message}"
    render json: { success: false, error: 'Failed to record acceptances' }
  end
end 
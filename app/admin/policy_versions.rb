ActiveAdmin.register PolicyVersion do
  permit_params :policy_type, :version, :content, :termly_embed_id, :active, 
                :requires_notification, :effective_date, :change_summary
  
  index do
    selectable_column
    id_column
    column :policy_type do |policy|
      policy.policy_type.humanize
    end
    column :version
    column :active do |policy|
      status_tag(policy.active? ? 'Active' : 'Inactive', 
                 class: policy.active? ? 'ok' : 'warn')
    end
    column :requires_notification
    column :effective_date
    column :created_at
    actions
  end
  
  show do
    attributes_table do
      row :policy_type do |policy|
        policy.policy_type.humanize
      end
      row :version
      row :active do |policy|
        status_tag(policy.active? ? 'Active' : 'Inactive', 
                   class: policy.active? ? 'ok' : 'warn')
      end
      row :requires_notification
      row :effective_date
      row :change_summary
      row :termly_embed_id
      row :content do |policy|
        if policy.content.present?
          pre policy.content
        else
          span "No content stored (using Termly embed)", class: 'empty'
        end
      end
      row :created_at
      row :updated_at
    end
    
    panel "Acceptance Count" do
      acceptance_count = PolicyAcceptance.where(
        policy_type: resource.policy_type, 
        policy_version: resource.version
      ).count
      
      div do
        strong "#{acceptance_count} users have accepted this policy version"
      end
      
      if acceptance_count > 0
        div style: "margin-top: 10px;" do
          link_to "View Acceptances", 
                  admin_policy_acceptances_path(q: { 
                    policy_type_eq: resource.policy_type,
                    policy_version_eq: resource.version 
                  }),
                  class: "button"
        end
      end
    end
  end
  
  form do |f|
    f.inputs 'Policy Version Details' do
      f.input :policy_type, as: :select, 
              collection: PolicyVersion::POLICY_TYPES.map { |t| [t.humanize, t] },
              hint: "Select the type of policy this version applies to"
      f.input :version, 
              hint: "Version number (e.g., v1.0, v1.1, v2.0)"
      f.input :termly_embed_id, 
              hint: "Termly embed ID for this policy version (get from Termly dashboard)"
      f.input :effective_date, as: :datetime_picker,
              hint: "When this policy version becomes effective"
      f.input :change_summary, as: :text, 
              hint: "Brief summary of what changed in this version"
      f.input :content, as: :text, 
              hint: "Optional: Store policy content directly (usually use Termly embed instead)"
      f.input :requires_notification, 
              hint: "Check if users must be notified of this change via email"
      f.input :active, 
              hint: "Only one version per policy type can be active at a time"
    end
    f.actions
  end
  
  member_action :activate, method: :patch do
    begin
      resource.activate!
      redirect_to admin_policy_versions_path, 
                  notice: "Policy version activated successfully! Users have been notified if required."
    rescue => e
      redirect_to admin_policy_versions_path, 
                  alert: "Failed to activate policy version: #{e.message}"
    end
  end
  
  action_item :activate, only: :show do
    unless resource.active?
      link_to "Activate This Version", 
              activate_admin_policy_version_path(resource), 
              method: :patch, 
              confirm: "This will deactivate all other versions of #{resource.policy_type.humanize} and may trigger user notifications. Continue?",
              class: "button"
    end
  end
  
  filter :policy_type, as: :select, collection: PolicyVersion::POLICY_TYPES.map { |t| [t.humanize, t] }
  filter :version
  filter :active
  filter :requires_notification
  filter :effective_date
  filter :created_at
end 
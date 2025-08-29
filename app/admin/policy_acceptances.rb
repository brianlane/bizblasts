ActiveAdmin.register PolicyAcceptance do
  actions :index, :show
  
  index do
    selectable_column
    id_column
    column :user do |acceptance|
      if acceptance.user
        link_to acceptance.user.full_name, admin_user_path(acceptance.user)
      else
        span "Deleted User", class: 'empty'
      end
    end
    column :policy_type do |acceptance|
      acceptance.policy_type.humanize
    end
    column :policy_version
    column :accepted_at do |acceptance|
      acceptance.accepted_at.strftime('%Y-%m-%d %H:%M:%S')
    end
    column :ip_address
    actions
  end
  
  show do
    attributes_table do
      row :user do |acceptance|
        if acceptance.user
          link_to acceptance.user.full_name, admin_user_path(acceptance.user)
        else
          span "Deleted User", class: 'empty'
        end
      end
      row :policy_type do |acceptance|
        acceptance.policy_type.humanize
      end
      row :policy_version
      row :accepted_at do |acceptance|
        acceptance.accepted_at.strftime('%Y-%m-%d %H:%M:%S %Z')
      end
      row :ip_address
      row :user_agent
      row :created_at
      row :updated_at
    end
    
    panel "User Details" do
      if resource.user
        attributes_table_for resource.user do
          row :email
          row :role do |user|
            user.role.humanize
          end
          row :business do |user|
            if user.business
              link_to user.business.name, admin_business_path(user.business.id)
            else
              span "No Business", class: 'empty'
            end
          end
          row :created_at
        end
      else
        div "User account has been deleted", class: 'empty'
      end
    end
    
    panel "Policy Version Details" do
      policy_version = PolicyVersion.find_by(
        policy_type: resource.policy_type, 
        version: resource.policy_version
      )
      
      if policy_version
        attributes_table_for policy_version do
          row :policy_type do |version|
            version.policy_type.humanize
          end
          row :version
          row :active do |version|
            status_tag(version.active? ? 'Active' : 'Inactive', 
                       class: version.active? ? 'ok' : 'warn')
          end
          row :effective_date
          row :change_summary
        end
      else
        div "Policy version #{resource.policy_version} no longer exists", class: 'empty'
      end
    end
  end
  
  filter :policy_type, as: :select, collection: PolicyAcceptance::POLICY_TYPES.map { |t| [t.humanize, t] }
  filter :policy_version
  filter :accepted_at
  filter :ip_address
  filter :user, as: :select, collection: -> { User.joins(:policy_acceptances).distinct.map { |u| [u.full_name, u.id] } }
  filter :created_at
end 
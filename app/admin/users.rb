ActiveAdmin.register User do
  permit_params :email, :first_name, :last_name, :role, :business_id, :active, :password, :password_confirmation, :staff_member_id

  # Filters
  filter :email
  filter :first_name
  filter :last_name
  filter :role, as: :select, collection: User.roles.keys.map { |r| [r.humanize, r] }
  filter :business, as: :select, collection: -> { Business.order(:name).pluck(:name, :id) }
  filter :active
  filter :created_at

  # Index Page Configuration
  index do
    selectable_column
    id_column
    column :email
    column "Name", :full_name
    column :role do |user|
      user.role&.humanize
    end
    column :business
    column "Staff Member" do |user|
      if user.business && user.staff_member
        link_to(user.staff_member.name, admin_staff_member_path(user.staff_member))
      else
        status_tag("N/A")
      end
    end
    column "Position" do |user|
      user.staff_member&.position
    end
    column "Associated Businesses" do |user|
      if user.client?
        user.associated_businesses.count
      else
        status_tag("N/A")
      end
    end
    column :active
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
          user.associated_businesses.map { |b| link_to(b.name, admin_business_path(b)) }.join(", ").html_safe
        end
      end
      
      row :staff_member do |user|
        if user.business && user.staff_member
          link_to(user.staff_member.name, admin_staff_member_path(user.staff_member))
        else
          "None"
        end
      end
      row :active
      row :created_at
      row :updated_at
      row :reset_password_sent_at
      row :remember_created_at
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

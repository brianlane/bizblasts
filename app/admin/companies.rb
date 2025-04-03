ActiveAdmin.register Company do
  # Permit parameters for create/update actions
  permit_params :name, :subdomain

  # Filter options for the index page
  filter :name
  filter :subdomain
  filter :created_at

  # Index page customization
  index do
    selectable_column
    id_column
    column :name
    column :subdomain
    column :created_at
    column "Users" do |company|
      company.users.count
    end
    column "Websites" do |company|
      company.client_websites.count
    end
    column "Active Websites" do |company|
      company.client_websites.where(active: true).count
    end
    actions
  end

  # Show page customization
  show do
    attributes_table do
      row :id
      row :name
      row :subdomain
      row :created_at
      row :updated_at
    end

    panel "Users" do
      table_for company.users do
        column :id
        column :email
        column :created_at
        column do |user|
          links = []
          links << link_to("View", admin_user_path(user))
          links << link_to("Edit", edit_admin_user_path(user))
          safe_join(links, " | ")
        end
      end
    end

    panel "Client Websites" do
      table_for company.client_websites do
        column :id
        column :name
        column :subdomain
        column :domain
        column :status
        column :active
        column do |website|
          links = []
          links << link_to("View", admin_client_website_path(website))
          links << link_to("Edit", edit_admin_client_website_path(website))
          safe_join(links, " | ")
        end
      end
    end

    panel "Services" do
      table_for company.services do
        column :id
        column :name
        column :price
        column :duration_minutes
        column :active
        column do |service|
          links = []
          links << link_to("View", admin_service_path(service))
          links << link_to("Edit", edit_admin_service_path(service))
          safe_join(links, " | ")
        end
      end
    end
  end

  # Form customization
  form do |f|
    f.inputs "Company Details" do
      f.input :name
      f.input :subdomain
    end
    f.actions
  end

  # Custom actions
  action_item :view_website, only: :show do
    link_to "View Websites", admin_client_websites_path(q: { company_id_eq: resource.id })
  end

  action_item :view_users, only: :show do
    link_to "View Users", admin_users_path(q: { company_id_eq: resource.id })
  end
  
  # Bulk actions for the index page
  batch_action :activate_websites do |ids|
    batch_action_collection.find(ids).each do |company|
      company.client_websites.update_all(active: true)
    end
    redirect_to collection_path, notice: "Websites activated for selected companies."
  end
  
  batch_action :deactivate_websites do |ids|
    batch_action_collection.find(ids).each do |company|
      company.client_websites.update_all(active: false)
    end
    redirect_to collection_path, notice: "Websites deactivated for selected companies."
  end
end

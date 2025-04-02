ActiveAdmin.register ServiceTemplate do
  # Permit parameters for create/update actions
  permit_params :name, :description, :category, :industry, :active, :status, 
                :features, :pricing, :content, :settings

  # Filter options for the index page
  filter :name
  filter :category
  filter :industry
  filter :active
  filter :status
  filter :created_at

  # Index page customization
  index do
    selectable_column
    id_column
    column :name
    column :category
    column :industry
    column :status do |template|
      status_tag template.status
    end
    column :active
    column "Websites" do |template|
      ClientWebsite.where(service_template_id: template.id).count
    end
    column :created_at
    actions
  end

  # Show page customization
  show do
    attributes_table do
      row :id
      row :name
      row :description
      row :category
      row :industry
      row :status
      row :active
      row :published_at
      row :created_at
      row :updated_at
      row :features do |template|
        ul do
          if template.features.present? && template.features.is_a?(Array)
            template.features.each do |feature|
              li feature.to_s
            end
          end
        end
      end
      row :pricing do |template|
        pre JSON.pretty_generate(template.pricing) if template.pricing.present?
      end
      row :content do |template|
        pre JSON.pretty_generate(template.content) if template.content.present?
      end
      row :settings do |template|
        pre JSON.pretty_generate(template.settings) if template.settings.present?
      end
      row :metadata do |template|
        pre JSON.pretty_generate(template.metadata) if template.metadata.present?
      end
    end

    panel "Websites Using This Template" do
      table_for ClientWebsite.where(service_template_id: resource.id) do
        column :id
        column :name
        column :company
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
  end

  # Form customization
  form do |f|
    f.semantic_errors
    
    f.inputs "Template Details" do
      f.input :name
      f.input :description
      f.input :category
      f.input :industry
      f.input :status, as: :select, collection: ['draft', 'published']
      f.input :active
    end
    
    f.inputs "Features and Content" do
      f.input :features, as: :text, input_html: { rows: 5 },
        hint: "JSON array format. Example: [\"Responsive Design\",\"SEO Friendly\",\"Contact Form\"]"
      f.input :pricing, as: :text, input_html: { rows: 5 },
        hint: "JSON format. Example: {\"monthly\":49.99,\"yearly\":499.99}"
      f.input :content, as: :text, input_html: { rows: 5 }, 
        hint: "JSON format for default content settings"
      f.input :settings, as: :text, input_html: { rows: 5 },
        hint: "JSON format for template configuration"
    end
    
    f.actions
  end

  # Custom actions
  action_item :publish, only: [:show, :edit] do
    if resource.status != 'published'
      link_to "Publish Template", publish_admin_service_template_path(resource), method: :put
    end
  end
  
  action_item :unpublish, only: [:show, :edit] do
    if resource.status == 'published'
      link_to "Unpublish Template", unpublish_admin_service_template_path(resource), method: :put
    end
  end
  
  action_item :toggle_active, only: [:show, :edit] do
    if resource.active
      link_to "Deactivate Template", deactivate_admin_service_template_path(resource), method: :put
    else
      link_to "Activate Template", activate_admin_service_template_path(resource), method: :put
    end
  end
  
  action_item :create_website, only: [:show] do
    link_to "Create Website with this Template", new_admin_client_website_path(service_template_id: resource.id)
  end
  
  # Custom member actions
  member_action :publish, method: :put do
    resource.update(status: 'published', published_at: Time.current)
    redirect_to resource_path, notice: "Template has been published!"
  end
  
  member_action :unpublish, method: :put do
    resource.update(status: 'draft', published_at: nil)
    redirect_to resource_path, notice: "Template has been unpublished!"
  end
  
  member_action :activate, method: :put do
    resource.update(active: true)
    redirect_to resource_path, notice: "Template has been activated!"
  end
  
  member_action :deactivate, method: :put do
    resource.update(active: false)
    redirect_to resource_path, notice: "Template has been deactivated!"
  end
  
  # Batch actions
  batch_action :publish do |ids|
    batch_action_collection.find(ids).each do |template|
      template.update(status: 'published', published_at: Time.current)
    end
    redirect_to collection_path, notice: "Templates have been published!"
  end
  
  batch_action :unpublish do |ids|
    batch_action_collection.find(ids).each do |template|
      template.update(status: 'draft', published_at: nil)
    end
    redirect_to collection_path, notice: "Templates have been unpublished!"
  end
  
  batch_action :activate do |ids|
    batch_action_collection.find(ids).each do |template|
      template.update(active: true)
    end
    redirect_to collection_path, notice: "Templates have been activated!"
  end
  
  batch_action :deactivate do |ids|
    batch_action_collection.find(ids).each do |template|
      template.update(active: false)
    end
    redirect_to collection_path, notice: "Templates have been deactivated!"
  end
end

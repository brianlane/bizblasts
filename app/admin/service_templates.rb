ActiveAdmin.register ServiceTemplate do
  # Permit parameters for create/update actions - revert to scalar symbols
  permit_params :name, :description, :category, :industry, :active, :status, 
                :features, :pricing, :content, :settings

  controller do
    # Parse JSON string params before create and update
    before_action :parse_json_params, only: [:create, :update]

    private

    def parse_json_params
      # Don't modify @resource directly here
      %i[features pricing content settings].each do |param|
        param_value = params[:service_template][param]
        if param_value.is_a?(String) && param_value.present?
          begin
            parsed_json = JSON.parse(param_value)
            # Replace the string param with the parsed hash/array
            params[:service_template][param] = parsed_json 
          rescue JSON::ParserError => e
            Rails.logger.error("Failed to parse JSON for #{param}: #{e.message}")
            # Add error directly to the params hash key that ActiveAdmin might check?
            # This is less standard, model validations are better.
            # For now, set to nil to avoid saving bad string, model validation should handle missing data if required.
            params[:service_template][param] = nil 
          end
        elsif param_value.blank?
           params[:service_template][param] = nil 
        end
      end
      # Let the standard controller action use the modified params[:service_template]
    end
  end

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
        pre JSON.pretty_generate(template.features) if template.features.present?
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

    active_admin_comments # Ensure comments are still shown if needed
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

ActiveAdmin.register ServiceTemplate do
  # Permit parameters: Use strings for enums as submitted by the form
  permit_params :name, :description, :industry, :active, :template_type, :structure, :published_at

  # Filter options for the index page
  filter :name
  filter :industry, as: :select, collection: ServiceTemplate.industries.keys
  filter :template_type, as: :select, collection: ServiceTemplate.template_types.keys
  filter :active
  filter :published_at
  filter :created_at

  # Index page customization
  index do
    selectable_column
    id_column
    column :name
    column :industry, sortable: :industry do |template|
      template.industry&.humanize
    end
    column :template_type do |template|
      template.template_type&.humanize
    end
    column :published do |template|
      status_tag(template.published? ? 'Published' : 'Draft', class: template.published? ? 'ok' : 'warn')
    end
    column :active
    column :created_at
    actions defaults: false do |template|
      item "View", resource_path(template)
      item "Edit", edit_resource_path(template)
      item "Delete", resource_path(template), method: :delete, data: { confirm: ("Are you sure?" unless Rails.env.test?) }
    end
  end

  # Show page customization
  show do
    attributes_table do
      row :id
      row :name
      row :description
      row :industry do |template|
        template.industry&.humanize
      end
      row :template_type do |template|
        template.template_type&.humanize
      end
      row :published do |template|
        template.published? ? "Published (#{template.published_at.strftime('%Y-%m-%d %H:%M')})" : "Draft"
      end
      row :active
      row :created_at
      row :updated_at
      row :structure do |template|
        pre JSON.pretty_generate(template.structure) if template.structure.present?
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
      f.input :industry, as: :select, collection: ServiceTemplate.industries.keys.map { |k| [k.humanize, k] }
      f.input :template_type, as: :select, collection: ServiceTemplate.template_types.keys.map { |k| [k.humanize, k] }
      f.input :active
    end

    f.inputs "Template Structure" do
      f.input :structure, as: :text, input_html: { rows: 15 },
        hint: "JSON format defining the pages and sections for this template. Example: { \"pages\": [ { \"title\": \"Home\", \"slug\": \"home\", ... } ] }"
    end

    f.actions
  end

  # Custom actions (adjusted for published_at)
  action_item :publish, only: [:show, :edit] do
    unless resource.published?
      link_to "Publish Template", publish_admin_service_template_path(resource), method: :put
    end
  end

  action_item :unpublish, only: [:show, :edit] do
    if resource.published?
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

  # Custom member actions (Using update!)
  member_action :publish, method: :put do
    resource.update!(published_at: Time.current)
    redirect_to resource_path, notice: "Template has been published!"
  end

  member_action :unpublish, method: :put do
    resource.update!(published_at: nil)
    redirect_to resource_path, notice: "Template has been unpublished!"
  end

  member_action :activate, method: :put do
    resource.update!(active: true)
    redirect_to resource_path, notice: "Template has been activated!"
  end

  member_action :deactivate, method: :put do
    resource.update!(active: false)
    redirect_to resource_path, notice: "Template has been deactivated!"
  end

  # Batch actions (Using update!)
  batch_action :publish do |ids|
    batch_action_collection.find(ids).each do |template|
      template.update!(published_at: Time.current)
    end
    redirect_to collection_path, notice: "Selected templates have been published!"
  end

  batch_action :unpublish do |ids|
    batch_action_collection.find(ids).each do |template|
      template.update!(published_at: nil)
    end
    redirect_to collection_path, notice: "Selected templates have been unpublished!"
  end

  batch_action :activate do |ids|
    batch_action_collection.find(ids).each do |template|
      template.update!(active: true)
    end
    redirect_to collection_path, notice: "Selected templates have been activated!"
  end

  batch_action :deactivate do |ids|
    batch_action_collection.find(ids).each do |template|
      template.update!(active: false)
    end
    redirect_to collection_path, notice: "Selected templates have been deactivated!"
  end

  # Controller customization to manually handle destroy and redirect
  controller do
    # Rescue from JSON parsing errors that might occur during assignment
    rescue_from JSON::ParserError do |exception|
      flash[:error] = "Invalid JSON format provided for Structure: #{exception.message}"
      # Determine redirect path based on action
      path = case params[:action]
             when 'create'
               new_resource_path
             when 'update'
               edit_resource_path(resource)
             else
               collection_path # Fallback
             end
      # Redirect back to the form, potentially preserving input if possible (ActiveAdmin might handle this)
      redirect_to path, status: :unprocessable_entity
    end

    # Explicitly define create action for logging
    def create
      Rails.logger.info("--- ServiceTemplate Create Action Start ---")
      Rails.logger.info("Params: #{params.inspect}")
      @service_template = ServiceTemplate.new(permitted_params[:service_template])
      Rails.logger.info("New ServiceTemplate object: #{@service_template.inspect}")
      
      if @service_template.save
        Rails.logger.info("ServiceTemplate saved successfully: #{@service_template.id}")
        redirect_to resource_path(@service_template), notice: "Service template was successfully created."
      else
        Rails.logger.error("ServiceTemplate save failed: #{@service_template.errors.full_messages.join(', ')}")
        render :new, status: :unprocessable_entity
      end
      Rails.logger.info("--- ServiceTemplate Create Action End ---")
    end

    # Explicitly define update action for logging
    def update
      Rails.logger.info("--- ServiceTemplate Update Action Start ---")
      Rails.logger.info("Params: #{params.inspect}")
      @service_template = ServiceTemplate.find(params[:id])
      Rails.logger.info("Found ServiceTemplate object: #{@service_template.inspect}")
      
      if @service_template.update(permitted_params[:service_template])
        Rails.logger.info("ServiceTemplate updated successfully: #{@service_template.id}")
        redirect_to resource_path(@service_template), notice: "Service template was successfully updated."
      else
        Rails.logger.error("ServiceTemplate update failed: #{@service_template.errors.full_messages.join(', ')}")
        render :edit, status: :unprocessable_entity
      end
      Rails.logger.info("--- ServiceTemplate Update Action End ---")
    end

    def destroy
      resource = ServiceTemplate.find(params[:id])
      resource.destroy
      flash[:notice] = "Service template was successfully destroyed."
      redirect_to collection_path
    end
  end
end

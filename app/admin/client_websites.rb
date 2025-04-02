ActiveAdmin.register ClientWebsite do
  # Permit parameters for create/update actions
  permit_params :company_id, :service_template_id, :name, :subdomain, :domain, 
                :active, :status, :custom_domain_enabled, :ssl_enabled,
                content: {}, settings: {}, theme: {}, seo_settings: {}

  # Set scopes for index page filtering
  scope :all, default: true
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :draft, -> { where(status: 'draft') }
  scope :published, -> { where(status: 'published') }

  # Filter options for the index page
  filter :company
  filter :service_template
  filter :name
  filter :subdomain
  filter :domain
  filter :active
  filter :status
  filter :created_at

  # Index page customization
  index do
    selectable_column
    id_column
    column :name
    column :company
    column :subdomain
    column :domain
    column :status do |website|
      status_tag website.status
    end
    column :active
    column :created_at
    actions
  end

  # Show page customization
  show do
    attributes_table do
      row :id
      row :company
      row :service_template
      row :name
      row :subdomain
      row :domain
      row :active
      row :status
      row :published_at
      row :custom_domain_enabled
      row :ssl_enabled
      row :created_at
      row :updated_at
      row :content do |website|
        pre JSON.pretty_generate(website.content) if website.content.present?
      end
      row :settings do |website|
        pre JSON.pretty_generate(website.settings) if website.settings.present?
      end
      row :theme do |website|
        pre JSON.pretty_generate(website.theme) if website.theme.present?
      end
      row :seo_settings do |website|
        pre JSON.pretty_generate(website.seo_settings) if website.seo_settings.present?
      end
      row :analytics do |website|
        pre JSON.pretty_generate(website.analytics) if website.analytics.present?
      end
      row :notes
    end
  end

  # Form customization
  form do |f|
    f.semantic_errors
    
    f.inputs "Website Details" do
      f.input :company
      f.input :service_template
      f.input :name
      f.input :subdomain
      f.input :domain
      f.input :status, as: :select, collection: ['draft', 'published']
      f.input :active
      f.input :custom_domain_enabled
      f.input :ssl_enabled
      f.input :notes
    end
    
    f.inputs "Advanced Settings" do
      f.input :content, as: :text, input_html: { rows: 5 }, 
        hint: "JSON format. Example: {\"headline\":\"Welcome\",\"description\":\"Our Services\"}"
      f.input :settings, as: :text, input_html: { rows: 5 },
        hint: "JSON format. Example: {\"show_contact\":true,\"enable_booking\":true}"
      f.input :theme, as: :text, input_html: { rows: 5 },
        hint: "JSON format. Example: {\"primary_color\":\"#336699\",\"font\":\"Arial\"}"
      f.input :seo_settings, as: :text, input_html: { rows: 5 },
        hint: "JSON format. Example: {\"meta_title\":\"Business Name\",\"meta_description\":\"Our services\"}"
    end
    
    f.actions
  end

  # Custom actions
  action_item :publish, only: [:show, :edit] do
    if resource.status != 'published'
      link_to "Publish Website", publish_admin_client_website_path(resource), method: :put
    end
  end
  
  action_item :unpublish, only: [:show, :edit] do
    if resource.status == 'published'
      link_to "Unpublish Website", unpublish_admin_client_website_path(resource), method: :put
    end
  end
  
  action_item :toggle_active, only: [:show, :edit] do
    if resource.active
      link_to "Deactivate Website", deactivate_admin_client_website_path(resource), method: :put
    else
      link_to "Activate Website", activate_admin_client_website_path(resource), method: :put
    end
  end
  
  action_item :view_company, only: [:show, :edit] do
    link_to "View Company", admin_company_path(resource.company)
  end
  
  # Custom member actions
  member_action :publish, method: :put do
    resource.update(status: 'published', published_at: Time.current)
    redirect_to resource_path, notice: "Website has been published!"
  end
  
  member_action :unpublish, method: :put do
    resource.update(status: 'draft', published_at: nil)
    redirect_to resource_path, notice: "Website has been unpublished!"
  end
  
  member_action :activate, method: :put do
    resource.update(active: true)
    redirect_to resource_path, notice: "Website has been activated!"
  end
  
  member_action :deactivate, method: :put do
    resource.update(active: false)
    redirect_to resource_path, notice: "Website has been deactivated!"
  end
  
  # Batch actions
  batch_action :publish do |ids|
    batch_action_collection.find(ids).each do |website|
      website.update(status: 'published', published_at: Time.current)
    end
    redirect_to collection_path, notice: "Websites have been published!"
  end
  
  batch_action :unpublish do |ids|
    batch_action_collection.find(ids).each do |website|
      website.update(status: 'draft', published_at: nil)
    end
    redirect_to collection_path, notice: "Websites have been unpublished!"
  end
  
  batch_action :activate do |ids|
    batch_action_collection.find(ids).each do |website|
      website.update(active: true)
    end
    redirect_to collection_path, notice: "Websites have been activated!"
  end
  
  batch_action :deactivate do |ids|
    batch_action_collection.find(ids).each do |website|
      website.update(active: false)
    end
    redirect_to collection_path, notice: "Websites have been deactivated!"
  end
end

ActiveAdmin.register DocumentTemplate do
  permit_params :business_id, :name, :document_type, :body, :active

  includes :business

  filter :business
  filter :document_type, as: :select, collection: -> { DocumentTemplate::DOCUMENT_TYPES }
  filter :version
  filter :active
  filter :updated_at

  scope :all, default: true
  scope :active

  index do
    selectable_column
    id_column
    column :business
    column :name
    column('Document Type') { |template| template.document_type.titleize }
    column :version
    column :active do |template|
      status_tag(template.active? ? 'Active' : 'Inactive', template.active? ? :ok : :warning)
    end
    column :updated_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :business
      row :name
      row('Document Type') { |template| template.document_type.titleize }
      row :version
      row :active
      row :created_at
      row :updated_at
    end

    panel 'Template Body' do
      div class: 'body-content' do
        if resource.body.present?
          simple_format(resource.body)
        else
          em 'No body content provided.'
        end
      end
    end
  end

  form do |f|
    f.semantic_errors

    f.inputs do
      f.input :business
      f.input :name
      f.input :document_type, as: :select, collection: DocumentTemplate::DOCUMENT_TYPES
      f.input :body, as: :text, input_html: { rows: 12 }
      f.input :active
    end

    f.actions
  end
end

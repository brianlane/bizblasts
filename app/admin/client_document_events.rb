ActiveAdmin.register ClientDocumentEvent do
  actions :index, :show

  includes :client_document, :business

  filter :business
  filter :client_document_id
  filter :event_type
  filter :created_at

  index do
    selectable_column
    id_column
    column :business
    column :client_document
    column :event_type
    column :actor_type
    column :actor_id
    column :ip_address
    column :created_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :business
      row :client_document
      row :event_type
      row :actor_type
      row :actor_id
      row :ip_address
      row :user_agent
      row :created_at
      row :updated_at
    end

    panel 'Event Data' do
      if resource.data.present?
        pre JSON.pretty_generate(resource.data)
      else
        em 'No structured data recorded.'
      end
    end
  end
end

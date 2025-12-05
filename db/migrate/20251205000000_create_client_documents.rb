class CreateClientDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :client_documents do |t|
      t.references :business, null: false, foreign_key: true
      t.references :tenant_customer, foreign_key: true
      t.references :documentable, polymorphic: true
      t.references :invoice, foreign_key: true
      t.string :document_type, null: false
      t.string :title
      t.text :body
      t.decimal :deposit_amount, precision: 10, scale: 2, default: 0.0, null: false
      t.boolean :payment_required, default: false, null: false
      t.boolean :signature_required, default: true, null: false
      t.string :currency, default: 'usd', null: false
      t.string :status, default: 'draft', null: false
      t.string :checkout_session_id
      t.string :payment_intent_id
      t.datetime :deposit_paid_at
      t.datetime :sent_at
      t.datetime :signed_at
      t.datetime :completed_at
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    create_table :document_signatures do |t|
      t.references :client_document, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.string :role, default: 'client', null: false
      t.string :signer_name, null: false
      t.string :signer_email
      t.text :signature_data
      t.datetime :signed_at
      t.string :ip_address
      t.string :user_agent
      t.integer :position
      t.timestamps
    end

    create_table :document_templates do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.string :document_type, null: false
      t.text :body, null: false
      t.boolean :active, default: true, null: false
      t.integer :version, default: 1, null: false
      t.timestamps
    end

    create_table :client_document_events do |t|
      t.references :client_document, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.string :event_type, null: false
      t.text :message
      t.jsonb :data, default: {}
      t.string :actor_type
      t.bigint :actor_id
      t.string :ip_address
      t.string :user_agent
      t.timestamps
    end

    add_index :client_documents, [:document_type, :status]
    add_index :client_documents, [:business_id, :status]
    add_index :client_documents, :checkout_session_id
    add_index :client_documents, :payment_intent_id
    add_index :document_signatures, [:client_document_id, :role]
    add_index :document_templates, [:business_id, :document_type, :active]
    add_index :client_document_events, [:client_document_id, :event_type]
  end
end

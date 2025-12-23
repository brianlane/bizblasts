# frozen_string_literal: true

class CreateJobAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :job_attachments do |t|
      t.references :business, null: false, foreign_key: true
      t.string :attachable_type, null: false
      t.bigint :attachable_id, null: false
      t.integer :attachment_type, default: 0, null: false
      t.string :title
      t.text :description
      t.text :instructions
      t.integer :visibility, default: 0, null: false
      t.references :uploaded_by_user, foreign_key: { to_table: :users }
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :job_attachments, [:attachable_type, :attachable_id]
    add_index :job_attachments, [:business_id, :attachment_type]
  end
end

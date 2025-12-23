# frozen_string_literal: true

class CreateJobFormTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :job_form_templates do |t|
      t.references :business, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :form_type, default: 0, null: false
      t.jsonb :fields, default: { 'fields' => [] }, null: false
      t.boolean :active, default: true, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :job_form_templates, [:business_id, :active]
    add_index :job_form_templates, [:business_id, :form_type]
  end
end

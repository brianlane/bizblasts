class CreateNotificationTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_templates do |t|
      t.references :business, null: false, foreign_key: true
      t.string :event_type
      t.integer :channel
      t.string :subject
      t.text :body

      t.timestamps
    end
  end
end

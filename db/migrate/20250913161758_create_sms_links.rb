class CreateSmsLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :sms_links do |t|
      t.text :original_url, null: false
      t.string :short_code, null: false
      t.integer :click_count, default: 0, null: false
      t.jsonb :tracking_params, default: {}
      t.datetime :last_clicked_at

      t.timestamps
    end
    
    add_index :sms_links, :short_code, unique: true
  end
end

class CreateEstimateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :estimate_messages do |t|
      t.references :estimate, null: false, foreign_key: true
      t.references :business, null: false, foreign_key: true
      t.string :sender_type, null: false  # 'customer' or 'business'
      t.string :sender_name
      t.string :sender_email
      t.text :message, null: false

      t.timestamps
    end

    add_index :estimate_messages, [:estimate_id, :created_at]
  end
end

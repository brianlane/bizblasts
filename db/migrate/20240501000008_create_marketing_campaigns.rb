class CreateMarketingCampaigns < ActiveRecord::Migration[8.0]
  def change
    create_table :marketing_campaigns do |t|
      t.string :name, null: false
      t.text :description
      t.integer :campaign_type, default: 0
      t.datetime :start_date
      t.datetime :end_date
      t.boolean :active, default: true
      t.integer :status, default: 0
      t.text :content
      t.jsonb :settings
      t.references :business, null: false, foreign_key: true
      t.references :promotion, foreign_key: true
      
      t.timestamps
    end
    
    create_table :campaign_recipients do |t|
      t.references :marketing_campaign, null: false, foreign_key: true
      t.references :tenant_customer, null: false, foreign_key: true
      t.datetime :sent_at
      t.boolean :opened, default: false
      t.boolean :clicked, default: false
      t.integer :status, default: 0
      
      t.timestamps
    end
    
    add_index :marketing_campaigns, [:name, :business_id], unique: true
  end
end

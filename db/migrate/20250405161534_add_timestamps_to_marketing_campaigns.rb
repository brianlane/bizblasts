class AddTimestampsToMarketingCampaigns < ActiveRecord::Migration[8.0]
  def change
    add_column :marketing_campaigns, :scheduled_at, :datetime
    add_column :marketing_campaigns, :started_at, :datetime
    add_column :marketing_campaigns, :completed_at, :datetime
  end
end

class AddCountersToMarketingCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :marketing_campaigns, :conversions_count, :integer, default: 0
    add_column :marketing_campaigns, :sent_count, :integer, default: 0
    add_column :marketing_campaigns, :opened_count, :integer, default: 0
    add_column :marketing_campaigns, :clicked_count, :integer, default: 0
  end
end

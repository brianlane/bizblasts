class AddCostToMarketingCampaigns < ActiveRecord::Migration[8.1]
  def change
    add_column :marketing_campaigns, :cost, :decimal, precision: 10, scale: 2, default: 0.0
  end
end

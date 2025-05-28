ActiveAdmin.register TaxRate do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :rate, :active, :business_id
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :rate, :active, :business_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # Enable batch actions
  batch_action :destroy, confirm: "Are you sure you want to delete these tax rates?" do |ids|
    deleted_count = 0
    failed_count = 0
    
    TaxRate.where(id: ids).find_each do |tax_rate|
      begin
        tax_rate.destroy!
        deleted_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to delete tax rate #{tax_rate.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{deleted_count} tax rates deleted successfully. #{failed_count} tax rates failed to delete."
    else
      redirect_to collection_path, notice: "#{deleted_count} tax rates deleted successfully."
    end
  end

  batch_action :activate, confirm: "Are you sure you want to activate these tax rates?" do |ids|
    updated_count = 0
    failed_count = 0
    
    TaxRate.where(id: ids).find_each do |tax_rate|
      begin
        tax_rate.update!(active: true)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to activate tax rate #{tax_rate.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} tax rates activated successfully. #{failed_count} tax rates failed to activate."
    else
      redirect_to collection_path, notice: "#{updated_count} tax rates activated successfully."
    end
  end

  batch_action :deactivate, confirm: "Are you sure you want to deactivate these tax rates?" do |ids|
    updated_count = 0
    failed_count = 0
    
    TaxRate.where(id: ids).find_each do |tax_rate|
      begin
        tax_rate.update!(active: false)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to deactivate tax rate #{tax_rate.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} tax rates deactivated successfully. #{failed_count} tax rates failed to deactivate."
    else
      redirect_to collection_path, notice: "#{updated_count} tax rates deactivated successfully."
    end
  end

  filter :name
  filter :rate
  filter :active
  filter :business

  index do
    selectable_column
    id_column
    column :name
    column :rate do |tax_rate|
      "#{tax_rate.rate}%" if tax_rate.rate
    end
    column :active
    column :business
    actions
  end

  form do |f|
    f.inputs do
      f.input :name
      f.input :rate, label: 'Rate (%)'
      f.input :active
      f.input :business, collection: Business.order(:name)
    end
    f.actions
  end
end 
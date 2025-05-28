ActiveAdmin.register Category do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :description, :active, :business_id
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :description, :active, :business_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # Enable batch actions
  batch_action :destroy, confirm: "Are you sure you want to delete these categories?" do |ids|
    deleted_count = 0
    failed_count = 0
    
    Category.where(id: ids).find_each do |category|
      begin
        category.destroy!
        deleted_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to delete category #{category.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{deleted_count} categories deleted successfully. #{failed_count} categories failed to delete."
    else
      redirect_to collection_path, notice: "#{deleted_count} categories deleted successfully."
    end
  end

  batch_action :activate, confirm: "Are you sure you want to activate these categories?" do |ids|
    updated_count = 0
    failed_count = 0
    
    Category.where(id: ids).find_each do |category|
      begin
        category.update!(active: true)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to activate category #{category.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} categories activated successfully. #{failed_count} categories failed to activate."
    else
      redirect_to collection_path, notice: "#{updated_count} categories activated successfully."
    end
  end

  batch_action :deactivate, confirm: "Are you sure you want to deactivate these categories?" do |ids|
    updated_count = 0
    failed_count = 0
    
    Category.where(id: ids).find_each do |category|
      begin
        category.update!(active: false)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to deactivate category #{category.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} categories deactivated successfully. #{failed_count} categories failed to deactivate."
    else
      redirect_to collection_path, notice: "#{updated_count} categories deactivated successfully."
    end
  end

  filter :name
  filter :description
  filter :active
  filter :business

  index do
    selectable_column
    id_column
    column :name
    column :description
    column :active
    column :business
    actions
  end

  form do |f|
    f.inputs do
      f.input :name
      f.input :description
      f.input :active
      f.input :business, collection: Business.order(:name)
    end
    f.actions
  end
end

ActiveAdmin.register ShippingMethod do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :description, :cost, :active, :business_id
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :description, :cost, :active, :business_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # Enable batch actions
  batch_action :destroy, confirm: "Are you sure you want to delete these shipping methods?" do |ids|
    deleted_count = 0
    failed_count = 0
    
    ShippingMethod.where(id: ids).find_each do |method|
      begin
        method.destroy!
        deleted_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to delete shipping method #{method.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{deleted_count} shipping methods deleted successfully. #{failed_count} shipping methods failed to delete."
    else
      redirect_to collection_path, notice: "#{deleted_count} shipping methods deleted successfully."
    end
  end

  batch_action :activate, confirm: "Are you sure you want to activate these shipping methods?" do |ids|
    updated_count = 0
    failed_count = 0
    
    ShippingMethod.where(id: ids).find_each do |method|
      begin
        method.update!(active: true)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to activate shipping method #{method.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} shipping methods activated successfully. #{failed_count} shipping methods failed to activate."
    else
      redirect_to collection_path, notice: "#{updated_count} shipping methods activated successfully."
    end
  end

  batch_action :deactivate, confirm: "Are you sure you want to deactivate these shipping methods?" do |ids|
    updated_count = 0
    failed_count = 0
    
    ShippingMethod.where(id: ids).find_each do |method|
      begin
        method.update!(active: false)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to deactivate shipping method #{method.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} shipping methods deactivated successfully. #{failed_count} shipping methods failed to deactivate."
    else
      redirect_to collection_path, notice: "#{updated_count} shipping methods deactivated successfully."
    end
  end

  filter :name
  filter :description
  filter :cost
  filter :active
  filter :business

  index do
    selectable_column
    id_column
    column :name
    column :description
    column :cost do |method|
      number_to_currency(method.cost) if method.cost
    end
    column :active
    column :business
    actions
  end

  form do |f|
    f.inputs do
      f.input :name
      f.input :description
      f.input :cost
      f.input :active
      f.input :business, collection: Business.order(:name)
    end
    f.actions
  end
end 
ActiveAdmin.register StaffMember do

  # See permitted parameters documentation:
  # https://github.com/activeadmin/activeadmin/blob/master/docs/2-resource-customization.md#setting-up-strong-parameters
  #
  # Uncomment all parameters which should be permitted for assignment
  #
  permit_params :name, :email, :phone, :active, :business_id
  #
  # or
  #
  # permit_params do
  #   permitted = [:name, :email, :phone, :active, :business_id]
  #   permitted << :other if params[:action] == 'create' && current_user.admin?
  #   permitted
  # end

  # Enable batch actions
  batch_action :destroy, confirm: "Are you sure you want to delete these staff members?" do |ids|
    deleted_count = 0
    failed_count = 0
    
    StaffMember.where(id: ids).find_each do |staff|
      begin
        staff.destroy!
        deleted_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to delete staff member #{staff.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{deleted_count} staff members deleted successfully. #{failed_count} staff members failed to delete."
    else
      redirect_to collection_path, notice: "#{deleted_count} staff members deleted successfully."
    end
  end

  batch_action :activate, confirm: "Are you sure you want to activate these staff members?" do |ids|
    updated_count = 0
    failed_count = 0
    
    StaffMember.where(id: ids).find_each do |staff|
      begin
        staff.update!(active: true)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to activate staff member #{staff.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} staff members activated successfully. #{failed_count} staff members failed to activate."
    else
      redirect_to collection_path, notice: "#{updated_count} staff members activated successfully."
    end
  end

  batch_action :deactivate, confirm: "Are you sure you want to deactivate these staff members?" do |ids|
    updated_count = 0
    failed_count = 0
    
    StaffMember.where(id: ids).find_each do |staff|
      begin
        staff.update!(active: false)
        updated_count += 1
      rescue => e
        failed_count += 1
        Rails.logger.error "Failed to deactivate staff member #{staff.id}: #{e.message}"
      end
    end
    
    if failed_count > 0
      redirect_to collection_path, alert: "#{updated_count} staff members deactivated successfully. #{failed_count} staff members failed to deactivate."
    else
      redirect_to collection_path, notice: "#{updated_count} staff members deactivated successfully."
    end
  end

  filter :name
  filter :email
  filter :phone
  filter :active
  filter :business

  index do
    selectable_column
    id_column
    column :name
    column :email
    column :phone
    column :active
    column :business
    actions
  end

  form do |f|
    f.inputs do
      f.input :name
      f.input :email
      f.input :phone
      f.input :active
      f.input :business, collection: Business.order(:name)
    end
    f.actions
  end
end

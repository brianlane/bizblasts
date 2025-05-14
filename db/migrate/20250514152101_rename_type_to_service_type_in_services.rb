class RenameTypeToServiceTypeInServices < ActiveRecord::Migration[8.0]
  def change
    rename_column :services, :type, :service_type
  end
end

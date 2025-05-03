class MakeServiceTemplateIdNullable < ActiveRecord::Migration[8.0]
  def change
    change_column_null :businesses, :service_template_id, true
  end
end 
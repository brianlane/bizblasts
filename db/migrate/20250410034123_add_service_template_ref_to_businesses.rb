class AddServiceTemplateRefToBusinesses < ActiveRecord::Migration[8.0]
  def change
    add_reference :businesses, :service_template, null: false, foreign_key: true
  end
end

class CreateProductServiceAddOns < ActiveRecord::Migration[8.0]
  def change
    create_table :product_service_add_ons do |t|
      t.bigint :product_id
      t.bigint :service_id

      t.timestamps
    end
  end
end

class CreatePages < ActiveRecord::Migration[8.0]
  def change
    create_table :pages do |t|
      t.references :business, null: false, foreign_key: true
      t.string :title
      t.string :slug
      t.integer :page_type
      t.boolean :published
      t.datetime :published_at
      t.integer :menu_order
      t.boolean :show_in_menu
      t.string :meta_description

      t.timestamps
    end
  end
end

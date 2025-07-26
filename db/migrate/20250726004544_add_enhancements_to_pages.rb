class AddEnhancementsToPages < ActiveRecord::Migration[8.0]
  def change
    add_column :pages, :view_count, :integer, default: 0, null: false
    add_column :pages, :priority, :integer, default: 0, null: false
    add_column :pages, :thumbnail_url, :string
    add_column :pages, :last_viewed_at, :datetime
    add_column :pages, :performance_score, :decimal, precision: 5, scale: 2
    
    add_index :pages, :view_count
    add_index :pages, :priority
    add_index :pages, :last_viewed_at
  end
end

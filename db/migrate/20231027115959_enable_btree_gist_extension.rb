class EnableBtreeGistExtension < ActiveRecord::Migration[7.1]
  def change
    enable_extension "btree_gist"
  end
end 
class CreateBlogPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :blog_posts do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :excerpt, null: false
      t.text :content, null: false
      t.string :author_name
      t.string :author_email
      t.string :category
      t.string :featured_image_url
      t.boolean :published, default: false
      t.datetime :published_at
      t.date :release_date

      t.timestamps
    end

    add_index :blog_posts, :slug, unique: true
    add_index :blog_posts, :published_at
    add_index :blog_posts, :category
    add_index :blog_posts, :published
  end
end

# frozen_string_literal: true

class AddSeoFieldsToPages < ActiveRecord::Migration[8.0]
  def change
    # Add SEO-specific fields to the pages table
    add_column :pages, :seo_title, :string unless column_exists?(:pages, :seo_title)
    add_column :pages, :seo_keywords, :text, array: true, default: [] unless column_exists?(:pages, :seo_keywords)
    add_column :pages, :og_title, :string unless column_exists?(:pages, :og_title)
    add_column :pages, :og_description, :text unless column_exists?(:pages, :og_description)
    add_column :pages, :canonical_url, :string unless column_exists?(:pages, :canonical_url)
    add_column :pages, :robots_directive, :string, default: 'index, follow' unless column_exists?(:pages, :robots_directive)
    add_column :pages, :sitemap_priority, :decimal, precision: 2, scale: 1, default: 0.5 unless column_exists?(:pages, :sitemap_priority)
    add_column :pages, :structured_data, :jsonb, default: {} unless column_exists?(:pages, :structured_data)
  end
end


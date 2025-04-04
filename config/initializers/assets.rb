# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Rails.root.join("node_modules")

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
Rails.application.config.assets.precompile += %w( admin.css admin.js )

# Add ActiveAdmin assets to precompilation list
Rails.application.config.assets.precompile += %w( active_admin.css active_admin.js )

# Special handling for test environment
if Rails.env.test?
  Rails.application.config.assets.compile = false
  Rails.application.config.assets.digest = false
  
  # Create stubs for asset helpers in test environment to avoid actual compilation
  if defined?(ActionView::Base)
    ActionView::Base.class_eval do
      def asset_path(source, options = {})
        "/assets/#{source}"
      end
      
      def stylesheet_link_tag(*sources)
        options = sources.extract_options!
        sources.map { |source| %(<link rel="stylesheet" media="screen" href="/assets/#{source}.css" />) }.join("\n").html_safe
      end
      
      def javascript_include_tag(*sources)
        options = sources.extract_options!
        sources.map { |source| %(<script src="/assets/#{source}.js"></script>) }.join("\n").html_safe
      end
    end
  end
end

# frozen_string_literal: true

# Helper module to handle asset pipeline in tests
module AssetPipelineHelper
  # Mock asset helpers to prevent asset compilation during tests
  def self.stub_asset_pipeline!
    # Override the Rails asset helpers to return dummy paths
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
    
    # Override Sprockets helpers
    if defined?(Sprockets::Rails::Helper)
      Sprockets::Rails::Helper.class_eval do
        def asset_path(source, options = {})
          "/assets/#{source}"
        end
      end
    end
    
    # Override Propshaft helpers
    if defined?(Propshaft::Helper)
      Propshaft::Helper.class_eval do
        def asset_path(source, options = {})
          "/assets/#{source}"
        end
      end
    end
  end
end 
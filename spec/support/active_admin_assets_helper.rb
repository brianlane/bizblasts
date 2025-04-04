# frozen_string_literal: true

# Helper module to stub ActiveAdmin assets in tests
module ActiveAdminAssetsHelper
  def self.stub_activeadmin_assets!
    # Skip asset compilation for ActiveAdmin in tests
    if defined?(ActiveAdmin)
      # Override asset tag helpers in ActiveAdmin views
      ActiveAdmin::Views::Pages::Base.class_eval do
        def build_active_admin_head
          within head do
            text_node "<!-- ActiveAdmin styles stub -->"
            text_node "<!-- ActiveAdmin JS stub -->"
          end
        end
      end
      
      # Create a basic stylesheet helper override for tests
      ActiveAdmin::Views::Header.class_eval do
        def build_global_navigation
          # Simplified nav for tests
          text_node "<!-- Admin Nav -->"
        end
      end
    end
  end
end 
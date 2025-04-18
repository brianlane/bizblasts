# frozen_string_literal: true

# Helper module to stub ActiveAdmin assets in tests
module ActiveAdminAssetsHelper
  def stub_activeadmin_assets!
    return unless defined?(ActiveAdmin)

    # Stub out asset helpers
    ActiveAdmin::Views::Pages::Base.class_eval do
      def build_active_admin_head
        within head do
          # Minimal CSS for tests
          text_node %{<style type="text/css">
            body.active_admin { padding-top: 50px; }
            #header { display: block; position: fixed; top: 0; left: 0; right: 0; }
          </style>}.html_safe
        end
      end
    end

    # Stub navigation
    ActiveAdmin::Views::Header.class_eval do
      def build_global_navigation
        text_node '<ul class="header-item tabs"></ul>'.html_safe
      end
    end

    # Stub utility navigation
    ActiveAdmin::Views::Header.class_eval do
      def build_utility_navigation
        text_node '<ul class="header-item utility-nav"></ul>'.html_safe
      end
    end
  end
end
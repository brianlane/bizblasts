ActiveAdmin.register_page "Debug" do
  menu priority: 100, label: "Tenant Debug"

  content title: "Multi-Tenant Debug Information" do
    div class: "tenant-debug" do
      columns do
        column do
          panel "Current Request" do
            attributes_table_for nil do
              row('Request Subdomain') { request.subdomain.presence || "(none)" }
              row('Current Tenant') { 
                current_tenant = ActsAsTenant.current_tenant
                current_tenant&.name || "(none)" 
              }
            end
          end

          panel "Available Tenants" do
            all_tenants = Business.pluck(:name, :subdomain)
            if all_tenants.any?
              table_for all_tenants do
                column("Business Name") { |tenant| tenant[0] }
                column("Subdomain") { |tenant| tenant[1] }
                column("Test URL (lvh.me)") do |tenant|
                  subdomain = tenant[1]
                  a href: "http://#{subdomain}.lvh.me:3000", target: "_blank" do
                    "#{subdomain}.lvh.me:3000"
                  end
                end
              end
            else
              para "No tenants found in the database."
            end
          end
        end

        column do
          panel "Test Your Tenants" do
            para "Use one of these methods to test multi-tenancy on localhost:"
            ul do
              li do
                strong "lvh.me: "
                span "Visit "
                a "lvh.me:3000", href: "http://lvh.me:3000"
                span " for public tenant, or "
                first_subdomain = Business.first&.subdomain
                if first_subdomain
                  a "#{first_subdomain}.lvh.me:3000", href: "http://#{first_subdomain}.lvh.me:3000"
                else
                  span "example.lvh.me:3000"
                end
                span " for specific tenant"
              end
              li do
                strong "127.0.0.1.xip.io: "
                span "Visit "
                a "127.0.0.1.xip.io:3000", href: "http://127.0.0.1.xip.io:3000"
                span " for public tenant, or "
                first_subdomain = Business.first&.subdomain
                if first_subdomain
                  a "#{first_subdomain}.127.0.0.1.xip.io:3000", href: "http://#{first_subdomain}.127.0.0.1.xip.io:3000"
                else
                  span "example.127.0.0.1.xip.io:3000"
                end
                span " for specific tenant"
              end
            end
          end

          panel "Multi-Tenancy Information" do
            para do
              span "This application uses "
              strong "acts_as_tenant"
              span " for multi-tenancy."
            end
            para "Data is separated through row-level tenant scoping rather than schema-level separation."
          end
        end
      end
    end
  end

  # Add a custom action button on the debug page
  action_item :go_home do
    link_to "Back to Homepage", "/"
  end
end 
# frozen_string_literal: true
ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: proc { I18n.t("active_admin.dashboard") }

  content title: proc { I18n.t("active_admin.dashboard") } do
    columns do
      column do
        panel "System Overview" do
          stats = {
            "Total Companies" => Company.count,
            "Total Users" => User.count,
            "Total Client Websites" => ClientWebsite.count,
            "Active Client Websites" => ClientWebsite.where(active: true).count,
            "Total Service Templates" => ServiceTemplate.count,
            "Total Software Products" => SoftwareProduct.count
          }
          
          table_for stats do
            column("Metric") { |stat| stat[0] }
            column("Count") { |stat| stat[1] }
          end
        end
      end

      column do
        panel "Recent Activity" do
          para "Recent companies created"
          table_for Company.order(created_at: :desc).limit(5) do
            column("Name") { |company| link_to(company.name, admin_company_path(company)) }
            column("Created") { |company| time_ago_in_words(company.created_at) + " ago" }
          end

          para "Recent client websites created"
          table_for ClientWebsite.order(created_at: :desc).limit(5) do
            column("Name") { |website| link_to(website.name, admin_client_website_path(website)) }
            column("Company") { |website| website.company.name }
            column("Status") { |website| status_tag(website.status) }
          end
        end
      end
    end
    
    columns do
      column do
        panel "Website Status Summary" do
          pie_data = {
            "Live" => ClientWebsite.where(status: "published").count,
            "Draft" => ClientWebsite.where(status: "draft").count,
            "Inactive" => ClientWebsite.where(active: false).count
          }
          
          table_for pie_data do
            column("Status") { |item| item[0] }
            column("Count") { |item| item[1] }
          end
        end
      end
      
      column do
        panel "Software Subscriptions Summary" do
          subscription_data = {
            "Active" => SoftwareSubscription.where(status: "active").count,
            "Trial" => SoftwareSubscription.where(status: "trial").count,
            "Expired" => SoftwareSubscription.where(status: "expired").count,
            "Cancelled" => SoftwareSubscription.where(status: "cancelled").count
          }
          
          table_for subscription_data do
            column("Status") { |item| item[0] }
            column("Count") { |item| item[1] }
          end
        end
      end
    end
    
    columns do
      column do
        panel "Performance Metrics" do
          para "Website analytics would be displayed here, integrating with web analytics APIs."
          para "This would include metrics like page load times, visitors, and conversion rates."
        end
      end
    end
  end
end

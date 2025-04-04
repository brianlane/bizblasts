# frozen_string_literal: true
ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: proc { I18n.t("active_admin.dashboard") }

  content title: proc { I18n.t("active_admin.dashboard") } do
    columns do
      column do
        panel "System Overview" do
          stats = {
            "Total Businesses" => Business.count,
            "Total Users" => User.count,
            "Total Services" => Service.count,
            "Total Staff Members" => StaffMember.count,
            "Total Bookings" => Booking.count
          }
          
          table_for stats do
            column("Metric") { |stat| stat[0] }
            column("Count") { |stat| stat[1] }
          end
        end
      end

      column do
        panel "Recent Activity" do
          para "Recent businesses created"
          table_for Business.order(created_at: :desc).limit(5) do
            column("Name") { |business| link_to(business.name, admin_business_path(business)) }
            column("Created") { |business| time_ago_in_words(business.created_at) + " ago" }
          end

          para "Recent users created"
          table_for User.order(created_at: :desc).limit(5) do
            column("Email") { |user| user.email }
            column("Created") { |user| time_ago_in_words(user.created_at) + " ago" }
          end
        end
      end
    end
    
    columns do
      column do
        panel "Booking Status Summary" do
          booking_data = {
            "Pending" => Booking.where(status: "pending").count,
            "Confirmed" => Booking.where(status: "confirmed").count,
            "Completed" => Booking.where(status: "completed").count,
            "Cancelled" => Booking.where(status: "cancelled").count
          }
          
          table_for booking_data do
            column("Status") { |item| item[0] }
            column("Count") { |item| item[1] }
          end
        end
      end
    end
    
    columns do
      column do
        panel "Performance Metrics" do
          para "Business analytics would be displayed here, integrating with analytics APIs."
          para "This would include metrics like bookings, revenue, and customer engagement rates."
        end
      end
    end

    panel "Administration Tools" do
      ul do
        li do
          link_to("Tenant Debug Information", admin_debug_path)
        end
      end
    end
  end
end

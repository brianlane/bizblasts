# frozen_string_literal: true

# ActiveAdmin page to list all websites with dynamic, clickable URLs
ActiveAdmin.register_page "Websites" do
  # Use the 'Websites' label in the menu
  menu priority: 2, label: "Websites"

  content title: "Websites" do
    panel "All Business Webpages" do
      # Retrieve all businesses ordered by name
      table_for Business.order(:name) do
        column :id
        column :name
        column :hostname
        column :host_type
        column :industry
        column :active
        column "URL" do |business|
          # Generate a clickable link using the Business#full_url helper
          link_to business.full_url, business.full_url, target: "_blank"
        end
      end
    end
  end
end 
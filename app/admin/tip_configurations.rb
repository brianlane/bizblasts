ActiveAdmin.register TipConfiguration do
  permit_params :business_id, :default_tip_percentages, :custom_tip_enabled, :tip_message

  # Define explicit filters
  filter :business
  filter :custom_tip_enabled, as: :select, collection: [['Yes', true], ['No', false]]
  filter :created_at
  filter :updated_at

  index do
    selectable_column
    id_column
    column :business do |config|
      link_to config.business.name, admin_business_path(config.business.id) if config.business
    end
    column :default_tip_percentages do |config|
      config.tip_percentage_options.map { |p| "#{p}%" }.join(", ")
    end
    column :custom_tip_enabled do |config|
      config.custom_tip_enabled? ? "Yes" : "No"
    end
    column :tip_message do |config|
      truncate(config.tip_message, length: 50) if config.tip_message
    end
    column :created_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :business do |config|
        link_to config.business.name, admin_business_path(config.business.id)
      end
      row :default_tip_percentages do |config|
        config.default_tip_percentages&.join(", ")
      end
      row :tip_percentage_options do |config|
        config.tip_percentage_options.map { |p| "#{p}%" }.join(", ")
      end
      row :custom_tip_enabled do |config|
        config.custom_tip_enabled? ? "Yes" : "No"
      end
      row :tip_message
      row :created_at
      row :updated_at
    end

    panel "Sample Tip Calculations" do
      table_for [25, 50, 100, 200] do |amount|
        column "Service Amount" do
          number_to_currency(amount)
        end
        resource.calculate_tip_amounts(amount).each do |tip_calc|
          column "#{tip_calc[:percentage]}% Tip" do
            number_to_currency(tip_calc[:amount])
          end
        end
        column "Total with Tips" do
          tips = resource.calculate_tip_amounts(amount)
          max_tip = tips.max_by { |t| t[:amount] }[:amount]
          number_to_currency(amount + max_tip)
        end
      end
    end

    active_admin_comments
  end

  form do |f|
    f.inputs "Tip Configuration" do
      f.input :business
      f.input :default_tip_percentages, as: :string, 
              hint: "Comma-separated percentages (e.g., 15,18,20,25)",
              input_html: { 
                value: f.object.default_tip_percentages&.join(","),
                placeholder: "15,18,20,25"
              }
      f.input :custom_tip_enabled, hint: "Allow customers to enter custom tip amounts"
      f.input :tip_message, as: :text, 
              hint: "Optional message shown to customers when selecting tips",
              input_html: { rows: 3 }
    end
    f.actions
  end

  controller do
    def permitted_params
      params.permit!
    end

    def update
      # Handle comma-separated tip percentages
      if params[:tip_configuration][:default_tip_percentages].is_a?(String)
        percentages = params[:tip_configuration][:default_tip_percentages]
                        .split(',')
                        .map(&:strip)
                        .map(&:to_i)
                        .select { |p| p > 0 && p <= 100 }
        params[:tip_configuration][:default_tip_percentages] = percentages
      end
      super
    end

    def create
      # Handle comma-separated tip percentages
      if params[:tip_configuration][:default_tip_percentages].is_a?(String)
        percentages = params[:tip_configuration][:default_tip_percentages]
                        .split(',')
                        .map(&:strip)
                        .map(&:to_i)
                        .select { |p| p > 0 && p <= 100 }
        params[:tip_configuration][:default_tip_percentages] = percentages
      end
      super
    end
  end
end
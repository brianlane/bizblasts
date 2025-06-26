class AddTemplateAppliedToBusiness < ActiveRecord::Migration[8.0]
  def change
    add_column :businesses, :template_applied, :string
  end
end

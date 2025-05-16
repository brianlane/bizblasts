class CreateIntegrationCredentials < ActiveRecord::Migration[8.0]
  def change
    create_table :integration_credentials do |t|
      t.references :business, null: false, foreign_key: true
      t.integer :provider
      t.jsonb :config

      t.timestamps
    end
  end
end

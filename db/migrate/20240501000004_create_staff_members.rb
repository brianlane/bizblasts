class CreateStaffMembers < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_members do |t|
      t.string :name, null: false
      t.string :email
      t.string :phone
      t.text :bio
      t.boolean :active, default: true
      t.references :business, null: false, foreign_key: true
      t.references :user, foreign_key: { to_table: :users, validate: false }
      
      t.timestamps
    end
    
    create_table :services_staff_members do |t|
      t.references :service, null: false, foreign_key: true
      t.references :staff_member, null: false, foreign_key: true
      
      t.timestamps
    end
    
    add_index :services_staff_members, [:service_id, :staff_member_id], unique: true, name: 'index_services_staff_members_uniqueness'
  end
end 
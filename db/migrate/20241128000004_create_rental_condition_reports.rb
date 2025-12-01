# frozen_string_literal: true

class CreateRentalConditionReports < ActiveRecord::Migration[8.0]
  def change
    create_table :rental_condition_reports do |t|
      t.references :rental_booking, null: false, foreign_key: true
      t.references :staff_member, foreign_key: true
      
      t.string :report_type, null: false  # checkout, return
      t.string :condition_rating  # excellent, good, fair, poor, damaged
      t.text :notes
      
      # Structured checklist (JSON array of items)
      # [{item: "Overall Appearance", condition: "good", notes: "Minor scratches"}]
      t.jsonb :checklist_items, default: []
      
      # Damage assessment
      t.decimal :damage_assessment_amount, precision: 10, scale: 2, default: 0
      t.text :damage_description
      
      t.timestamps
    end

    add_index :rental_condition_reports, [:rental_booking_id, :report_type]
  end
end


# frozen_string_literal: true

class AddDocumentTemplateToServicesAndProducts < ActiveRecord::Migration[8.1]
  def change
    add_reference :services, :document_template, null: true, foreign_key: true
    add_reference :products, :document_template, null: true, foreign_key: true
  end
end


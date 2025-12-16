# frozen_string_literal: true

class AddTokenToClientDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :client_documents, :token, :string
    add_index :client_documents, :token, unique: true

    # Backfill existing records with tokens
    reversible do |dir|
      dir.up do
        ClientDocument.find_each do |doc|
          doc.update_column(:token, SecureRandom.hex(16))
        end
        
        # Make token non-nullable after backfill
        change_column_null :client_documents, :token, false
      end
    end
  end
end


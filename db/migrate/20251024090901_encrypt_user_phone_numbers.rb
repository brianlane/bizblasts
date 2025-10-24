# frozen_string_literal: true

class EncryptUserPhoneNumbers < ActiveRecord::Migration[8.0]
  # This migration adds phone_ciphertext column and encrypts existing phone numbers in users table
  # Using deterministic encryption to maintain query capabilities

  def up
    # Add phone_ciphertext column for Active Record Encryption
    add_column :users, :phone_ciphertext, :text unless column_exists?(:users, :phone_ciphertext)

    # Add index on phone_ciphertext for performance
    add_index :users, :phone_ciphertext, if_not_exists: true

    # Encrypt existing phone numbers
    User.reset_column_information if User.respond_to?(:reset_column_information)
    if User.column_names.include?("phone")
      say_with_time "Encrypting phone numbers in users" do
        User.where.not(phone: nil).find_each do |user|
          # Read the raw plaintext value (skip decryption) and then write it back so
          # Active Record encrypts it on save
          plaintext = ActiveRecord::Encryption.without_encryption { user.read_attribute(:phone) }

          # Skip rows where ciphertext column is not available yet or already populated
          unless user.has_attribute?(:phone_ciphertext)
            Rails.logger&.debug("Skipping user ##{user.id} during phone encryption – ciphertext column missing")
            next
          end

          next if user.read_attribute(:phone_ciphertext).present? || plaintext.blank?

          user.update!(phone: plaintext)
        end
      end
    end
  end

  def down
    # Remove index
    remove_index :users, :phone_ciphertext, if_exists: true

    # Remove column
    remove_column :users, :phone_ciphertext, if_exists: true

    # Decryption happens automatically when models are loaded
    say "Phone numbers will be automatically decrypted when accessed"
  end
end

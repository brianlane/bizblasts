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

    # Use a lightweight model to read legacy plaintext without invoking modern callbacks/encryption
    legacy_user_class = Class.new(ActiveRecord::Base) do
      self.table_name = "users"
      self.inheritance_column = :_type_disabled
    end

    legacy_user_class.reset_column_information

    if legacy_user_class.column_names.include?("phone")
      encryptor = User.type_for_attribute("phone")
      touch_updated_at = legacy_user_class.column_names.include?("updated_at")

      say_with_time "Encrypting phone numbers in users" do
        legacy_user_class.where.not(phone: nil).find_each do |legacy_user|
          plaintext = legacy_user[:phone]
          ciphertext = legacy_user[:phone_ciphertext]
          next if plaintext.blank? || ciphertext.present?

          normalized = normalize_phone_for_migration(plaintext)
          updates = {
            phone: normalized,
            phone_ciphertext: normalized.present? ? encryptor.serialize(normalized) : nil
          }
          updates[:updated_at] = Time.current if touch_updated_at

          legacy_user.update_columns(updates)
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

  private

  def normalize_phone_for_migration(raw_phone)
    return nil if raw_phone.nil?

    phone_str = raw_phone.to_s
    return nil if phone_str.blank?

    digits = phone_str.gsub(/\D/, "")
    return nil if digits.blank?

    minimum_digits = 7
    # Reject phone numbers that are too short to be valid
    return nil if digits.length < minimum_digits

    default_country_code = "1"
    normalized_digits = digits.length == 10 ? "#{default_country_code}#{digits}" : digits
    "+#{normalized_digits}"
  end
end

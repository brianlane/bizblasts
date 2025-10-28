namespace :data do
  desc 'Normalize and re-encrypt user phone numbers'
  task fix_user_phone_encryption: :environment do
    total   = 0
    updated = 0
    errors  = 0

    puts "[UserPhoneFix] Starting normalization run..."

    User.find_in_batches(batch_size: 1000) do |batch|
      batch.each do |user|
        total += 1

        begin
          raw_phone = begin
            user.phone
          rescue ActiveRecord::Encryption::Errors::Decryption,
                 ActiveRecord::Encryption::Errors::Encoding,
                 JSON::ParserError
            user.read_attribute_before_type_cast('phone')
          end

          next if raw_phone.blank?

          normalized = PhoneNormalizer.normalize(raw_phone)

          if normalized == user.phone
            next
          end

          user.phone = normalized

          begin
            if user.save(validate: false)
              updated += 1
            else
              errors += 1
              warn "[UserPhoneFix] Validation failure for User ##{user.id}: #{user.errors.full_messages.join(', ')}"
            end
          rescue ActiveRecord::Encryption::Errors::Decryption,
                 ActiveRecord::Encryption::Errors::Encoding,
                 JSON::ParserError => e
            errors += 1
            warn "[UserPhoneFix] Encryption error for User ##{user.id}: #{e.class} - #{e.message}"
          end
        rescue => e
          errors += 1
          warn "[UserPhoneFix] Unexpected error for User ##{user.id}: #{e.class} - #{e.message}"
        end
      end
    end

    puts "[UserPhoneFix] Scan complete. Processed: #{total}, Updated: #{updated}, Errors: #{errors}"
  end
end

# db/migrate/YYYYMMDDHHMMSS_update_industry_values_for_businesses.rb
class UpdateIndustryValuesForBusinesses < ActiveRecord::Migration[7.1] # Adjust Rails version if needed
  # This mapping should cover the *actual string values* stored by the OLD enum
  # to the *new string values* that the NEW enum will store.
  OLD_STORED_VALUE_TO_NEW_STRING_MAPPING = {
    'hair_salon' => "Hair Salons",
    'beauty_spa' => "Beauty Spa",
    'massage_therapy' => "Massage Therapy",
    'fitness_studio' => "Other", # No direct match in new showcase, mapping to "Other"
    'tutoring_service' => "Tutoring",
    'cleaning_service' => "Cleaning Services",
    'handyman_service' => "Handyman Service",
    'pet_grooming' => "Pet Grooming",
    'photography' => "Photography",
    'consulting' => "Consulting",
    'other' => "Other"
    # Add any other old *stored string values* that need mapping
  }.freeze

  def up
    # Ensure the Business model is loaded with its new enum definition for `Business.industries`
    # This might require `Rails.application.eager_load!` if run in a context where models aren't fully loaded.
    # However, direct SQL or careful model usage is often safer in migrations.
    # For this migration, we directly reference the Business model, assuming it reflects the latest code.

    Business.reset_column_information # Ensures fresh column information

    Business.find_each do |business|
      # Read the raw value from the database for the industry column
      raw_old_industry_value = business.read_attribute_before_type_cast(:industry)

      if OLD_STORED_VALUE_TO_NEW_STRING_MAPPING.key?(raw_old_industry_value)
        new_industry_value = OLD_STORED_VALUE_TO_NEW_STRING_MAPPING[raw_old_industry_value]
        # Using update_column to skip validations and callbacks, which is common in migrations
        business.update_column(:industry, new_industry_value)
        puts "Updated Business ID: #{business.id} industry from '#{raw_old_industry_value}' to '#{new_industry_value}'"
      elsif Business.industries.value?(raw_old_industry_value)
        # This checks if the raw value is already one of the NEW valid string enum values
        puts "Business ID: #{business.id} industry '#{raw_old_industry_value}' is already a valid new value. No change needed."
      else
        # If the raw value is not in our explicit mapping and not a valid new value,
        # it's an edge case. Map to "Other" or log for manual review.
        puts "WARN: Business ID: #{business.id} has unrecognized industry value '#{raw_old_industry_value}'. Mapping to 'Other'."
        business.update_column(:industry, "Other")
      end
    end
  end

  def down
    # Reverting this requires knowing which new string maps back to which old stored string.
    # This can be complex if multiple old values mapped to a single new value (e.g., "Other").
    # A simple reversal might be:
    # NEW_STRING_TO_OLD_STORED_VALUE_MAPPING = OLD_STORED_VALUE_TO_NEW_STRING_MAPPING.invert
    #
    # Business.find_each do |business|
    #   current_industry_value = business.read_attribute_before_type_cast(:industry)
    #   if NEW_STRING_TO_OLD_STORED_VALUE_MAPPING.key?(current_industry_value)
    #     original_old_value = NEW_STRING_TO_OLD_STORED_VALUE_MAPPING[current_industry_value]
    #     business.update_column(:industry, original_old_value)
    #     puts "Reverted Business ID: #{business.id} industry from '#{current_industry_value}' to '#{original_old_value}'"
    #   else
    #     # If it was mapped to "Other" from an unrecognized source, reverting is ambiguous.
    #     puts "WARN: Business ID: #{business.id} industry '#{current_industry_value}' cannot be automatically reverted to a specific old value."
    #   end
    # end
    raise ActiveRecord::IrreversibleMigration, "Reverting industry values from new strings back to potentially varied old short strings is complex and requires careful manual mapping if truly needed. The default 'Other' mappings are particularly tricky to reverse automatically."
  end
end 
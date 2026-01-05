class MigrateExistingGallerySections < ActiveRecord::Migration[8.1]
  def up
    # Set default section_config for existing gallery sections
    PageSection.where(section_type: :gallery).find_each do |section|
      if section.section_config.blank? || section.section_config.empty?
        section.update_columns(
          section_config: {
            'layout' => 'grid',
            'columns' => 3,
            'photo_source_mode' => 'business',
            'show_hover_effects' => true,
            'show_photo_titles' => true,
            'max_photos' => 50
          }
        )
      end
    end
  end

  def down
    # No-op - we don't need to reverse this migration
  end
end

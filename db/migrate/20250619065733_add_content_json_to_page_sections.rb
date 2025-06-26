class AddContentJsonToPageSections < ActiveRecord::Migration[8.0]
  def up
    # First, migrate existing ActionText content to JSON format in the text column
    # Only proceed if the ActionText table exists
    return unless ActiveRecord::Base.connection.table_exists?('action_text_rich_texts')
    
    # Get ActionText content that needs to be migrated
    action_text_contents = ActiveRecord::Base.connection.execute(
      "SELECT record_id, body FROM action_text_rich_texts WHERE record_type = 'PageSection' AND name = 'content'"
    )
    
    action_text_contents.each do |row|
      section_id = row['record_id']
      body_text = row['body']
      if body_text.include?('=>')
        # Parse Ruby hash format to JSON
        begin
          # Remove HTML wrapper and get the hash string
          hash_match = body_text.match(/\{[^}]+\}/)
          if hash_match
            hash_string = hash_match[0]
            # Convert HTML entities back to normal characters
            hash_string = hash_string.gsub('&gt;', '>').gsub('&lt;', '<').gsub('&amp;', '&')
            # Safely evaluate the Ruby hash and convert to JSON format
            content_hash = eval(hash_string)
            json_string = content_hash.to_json.gsub("'", "''")
            ActiveRecord::Base.connection.execute(
              "UPDATE page_sections SET content = '#{json_string}' WHERE id = #{section_id}"
            )
            puts "Migrated section #{section_id}: #{content_hash}"
          end
        rescue => e
          puts "Failed to migrate section #{section_id}: #{e.message}"
        end
      end
    end
    
    # Now change the column type from text to JSON, using USING clause
    # Only proceed if the content column exists and is not already JSON
    if ActiveRecord::Base.connection.column_exists?(:page_sections, :content)
      column = ActiveRecord::Base.connection.columns(:page_sections).find { |c| c.name == 'content' }
      unless column.sql_type.include?('json')
        execute "ALTER TABLE page_sections ALTER COLUMN content TYPE json USING content::json"
        puts "Successfully converted content column to JSON type"
      else
        puts "Content column is already JSON type, skipping conversion"
      end
    else
      puts "Content column does not exist, skipping conversion"
    end
  end
  
  def down
    change_column :page_sections, :content, :text
  end
end

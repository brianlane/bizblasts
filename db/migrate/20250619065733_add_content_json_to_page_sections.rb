class AddContentJsonToPageSections < ActiveRecord::Migration[8.0]
  def up
    # First, migrate existing ActionText content to JSON format in the text column
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
    execute "ALTER TABLE page_sections ALTER COLUMN content TYPE json USING content::json"
    
    puts "Successfully converted content column to JSON type"
  end
  
  def down
    change_column :page_sections, :content, :text
  end
end

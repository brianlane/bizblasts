class MarkdownRenderer
  class << self
    def render(text)
      return '' if text.blank?
      
      # Preprocess the text to handle common formatting issues
      processed_text = preprocess_content(text)
      
      renderer.render(processed_text).html_safe
    end

    private

    def preprocess_content(text)
      # Normalize line endings
      text = text.gsub(/\r\n|\r/, "\n")
      
      # Convert bullet point characters to markdown dashes
      # Handle each bullet character individually and ensure they're at line start
      text = text.gsub(/^[•]\s+(.+)$/, '- \1')
      text = text.gsub(/^[·]\s+(.+)$/, '- \1')
      text = text.gsub(/^[▪]\s+(.+)$/, '- \1')
      text = text.gsub(/^[▫]\s+(.+)$/, '- \1')
      text = text.gsub(/^[‣]\s+(.+)$/, '- \1')
      text = text.gsub(/^[⁃]\s+(.+)$/, '- \1')
      
      # Ensure proper spacing around lists by adding blank lines before and after list groups
      lines = text.split("\n")
      processed_lines = []
      in_list = false
      
      lines.each_with_index do |line, index|
        is_list_item = line.match?(/^[-*+]\s+/)
        previous_line = index > 0 ? lines[index - 1] : ""
        
        if is_list_item
          # Add blank line before list if not already in a list and previous line isn't blank
          if !in_list && !previous_line.strip.empty? && processed_lines.last && !processed_lines.last.strip.empty?
            processed_lines << ""
          end
          in_list = true
        else
          # Add blank line after list if we were in a list and current line isn't blank
          if in_list && !line.strip.empty?
            processed_lines << ""
          end
          in_list = false
        end
        
        processed_lines << line
      end
      
      text = processed_lines.join("\n")
      
      # Ensure double line breaks before major sections (bold headers)
      text = text.gsub(/\n(\*\*[^*]+\*\*)/m, "\n\n\\1")
      
      # Clean up multiple consecutive line breaks
      text = text.gsub(/\n{3,}/, "\n\n")
      
      text.strip
    end

    def renderer
      @renderer ||= Redcarpet::Markdown.new(
        html_renderer,
        markdown_options
      )
    end

    def html_renderer
      SyntaxHighlightingRenderer.new
    end

    def markdown_options
      {
        autolink: true,                 # Auto-link URLs
        tables: true,                   # Parse tables
        fenced_code_blocks: true,       # Parse ``` code blocks
        strikethrough: true,            # Parse ~~text~~
        lax_spacing: true,              # Relax spacing requirements
        space_after_headers: true,      # Require space after # headers
        superscript: true,              # Parse ^superscript^
        underline: true,                # Parse _underline_ (separate from emphasis)
        highlight: true,                # Parse ==highlight==
        quote: true,                    # Parse "smart quotes"
        footnotes: true,                # Parse footnotes [^1]
        no_intra_emphasis: true,        # Don't parse emphasis inside words
        disable_indented_code_blocks: false, # Allow 4-space indented code
        hard_wrap: true,               # Convert line breaks to <br>
        with_toc_data: true            # Add IDs to headers for table of contents
      }
    end
  end
end 
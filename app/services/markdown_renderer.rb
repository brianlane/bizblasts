class MarkdownRenderer
  class << self
    def render(text)
      return '' if text.blank?
      
      renderer.render(text).html_safe
    end

    private

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
        disable_indented_code_blocks: false # Allow 4-space indented code
      }
    end
  end
end 
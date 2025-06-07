class SyntaxHighlightingRenderer < Redcarpet::Render::HTML
  def initialize(options = {})
    super(options.merge(
      filter_html: true,
      no_intra_emphasis: true,
      tables: true,
      fenced_code_blocks: true,
      autolink: true,
      strikethrough: true,
      lax_spacing: true,
      space_after_headers: true,
      superscript: true,
      underline: true,
      highlight: true,
      quote: true,
      footnotes: true,
      link_attributes: { target: '_blank', rel: 'noopener' }
    ))
  end

  def block_code(code, language)
    if language.present?
      # Rouge syntax highlighting
      lexer = Rouge::Lexer.find(language) || Rouge::Lexers::PlainText.new
      formatter = Rouge::Formatters::HTML.new(
        css_class: 'highlight',
        line_numbers: false
      )
      
      highlighted_code = formatter.format(lexer.lex(code))
      
      %(<div class="code-block">
          <div class="code-header">
            <span class="language-label">#{language}</span>
          </div>
          <pre class="code-content"><code class="language-#{language}">#{highlighted_code}</code></pre>
        </div>)
    else
      # Plain code block without highlighting
      %(<pre><code>#{code}</code></pre>)
    end
  end

  def codespan(code)
    %(<code class="inline-code">#{code}</code>)
  end

  def table(header, body)
    %(<div class="table-wrapper">
        <table class="markdown-table">
          <thead>#{header}</thead>
          <tbody>#{body}</tbody>
        </table>
      </div>)
  end

  def blockquote(quote)
    %(<blockquote class="markdown-blockquote">#{quote}</blockquote>)
  end

  def header(text, header_level)
    anchor_id = text.downcase.gsub(/[^a-z0-9\s]/, '').gsub(/\s+/, '-')
    %(<h#{header_level} id="#{anchor_id}" class="markdown-header markdown-h#{header_level}">
        #{text}
        <a href="##{anchor_id}" class="header-link">#</a>
      </h#{header_level}>)
  end

  def list(contents, list_type)
    tag = list_type == :ordered ? 'ol' : 'ul'
    %(<#{tag} class="markdown-list markdown-#{tag}">
#{contents}
</#{tag}>)
  end

  def list_item(text, list_type)
    %(<li class="markdown-list-item">#{text.strip}</li>)
  end

  def paragraph(text)
    # Ensure proper paragraph spacing
    %(<p>#{text}</p>)
  end
end 
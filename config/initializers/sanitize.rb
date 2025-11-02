# frozen_string_literal: true

# Sanitize Configuration for Markdown Content
#
# This initializer defines custom Sanitize configurations for different
# types of user-generated content. These configs provide a single source
# of truth for HTML sanitization rules across the application.
#
# Documentation: https://github.com/rgrove/sanitize

# Markdown Content Configuration
# Used for: Blog posts, product descriptions, service descriptions, etc.
# Based on: Sanitize::Config::RELAXED with additional allowed elements
Sanitize::Config::MARKDOWN = Sanitize::Config::RELAXED.merge(
  # Allow additional HTML elements commonly used in markdown
  elements: Sanitize::Config::RELAXED[:elements] + %w[
    table thead tbody tfoot tr th td
    details summary
    mark
    abbr
    kbd
    samp
    var
    sub sup
    ins del
  ],

  # Configure allowed attributes per element
  attributes: Sanitize::Config::RELAXED[:attributes].merge(
    'a' => %w[href title rel target],
    'img' => %w[src alt title width height],
    'table' => %w[class],
    'th' => %w[scope colspan rowspan],
    'td' => %w[colspan rowspan],
    'code' => %w[class], # For syntax highlighting classes
    'pre' => %w[class],  # For code block styling
    'blockquote' => %w[cite]
  ),

  # Protocol whitelist for links and images
  protocols: {
    'a' => {
      'href' => ['http', 'https', 'mailto', 'tel', 'sms', :relative]
    },
    'img' => {
      'src' => ['http', 'https', 'data', :relative]
    },
    'blockquote' => {
      'cite' => ['http', 'https', :relative]
    }
  },

  # Transform configuration
  transformers: [
    # Add rel="noopener noreferrer" to external links
    lambda do |env|
      node = env[:node]
      return unless env[:node_name] == 'a'
      return unless node['href']

      # Check if it's an external link
      href = node['href']
      is_external = href.start_with?('http://', 'https://') &&
                   !href.include?(ENV.fetch('APPLICATION_HOST', 'bizblasts.com'))

      if is_external
        node['rel'] = 'noopener noreferrer'
        node['target'] = '_blank'
      end
    end,

    # Remove empty paragraphs and divs
    lambda do |env|
      node = env[:node]
      return unless %w[p div].include?(env[:node_name])
      return unless node.text.strip.empty? && node.children.empty?

      node.unlink
    end
  ]
)

# Strict Configuration (for user comments, etc.)
# More restrictive than MARKDOWN - no images, tables, or complex HTML
Sanitize::Config::STRICT_MARKDOWN = Sanitize::Config::BASIC.merge(
  elements: %w[
    p br strong em a ul ol li blockquote code pre
    h1 h2 h3 h4 h5 h6
  ],

  attributes: {
    'a' => %w[href title rel],
    'code' => %w[class]
  },

  protocols: {
    'a' => {
      'href' => ['http', 'https', 'mailto', :relative]
    }
  }
)

# Plain Text Configuration (strips all HTML)
# Use for: Names, titles, short descriptions
Sanitize::Config::PLAIN_TEXT = {
  elements: [],
  attributes: {},
  remove_contents: true,
  whitespace_elements: []
}

# Log configuration on initialization
Rails.logger.info "Sanitize configurations initialized: MARKDOWN, STRICT_MARKDOWN, PLAIN_TEXT"

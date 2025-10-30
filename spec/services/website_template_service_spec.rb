# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebsiteTemplateService, type: :service do
  # Note: Tests for sanitize_css_value and sanitize_css_property_name have been
  # moved to spec/concerns/css_sanitizer_spec.rb since these methods now use
  # the CssSanitizer module

  describe '.generate_theme_css' do
    context 'with valid theme data' do
      let(:theme_data) do
        {
          'color_scheme' => {
            'primary' => '#3b82f6',
            'secondary' => '#1e40af',
            'accent' => '#f59e0b'
          },
          'typography' => {
            'font_family' => 'Arial, sans-serif',
            'font_size' => '16px'
          }
        }
      end

      it 'generates CSS variables from theme data' do
        result = described_class.generate_theme_css(theme_data)
        expect(result).to include('--color-primary: #3b82f6')
        expect(result).to include('--color-secondary: #1e40af')
        expect(result).to include('--color-accent: #f59e0b')
        expect(result).to include('--font-family: Arial, sans-serif')
        expect(result).to include('--font-size: 16px')
      end

      it 'wraps variables in :root block' do
        result = described_class.generate_theme_css(theme_data)
        expect(result).to start_with(':root {')
        expect(result).to end_with('}')
      end
    end

    context 'with malicious theme data' do
      it 'sanitizes XSS attempts in color values' do
        malicious_data = {
          'color_scheme' => {
            'primary' => 'red; </style><script>alert("XSS")</script><style>'
          }
        }

        result = described_class.generate_theme_css(malicious_data)
        expect(result).not_to include('<script>')
        expect(result).not_to include('</style>')
        expect(result).not_to include('<')
        expect(result).not_to include('>')
        # The text 'alert' may remain but without tags/brackets it's harmless in CSS context
      end

      it 'sanitizes CSS context escape attempts' do
        malicious_data = {
          'color_scheme' => {
            'primary' => 'red; } body { display: none; } .x {'
          }
        }

        result = described_class.generate_theme_css(malicious_data)
        # The key protection is that curly braces are removed from the value
        expect(result).to include(':root {') # Opening brace from :root
        expect(result).to end_with('}') # Closing brace from :root
        # The value itself should not contain braces (they're removed by sanitization)
        # So there should only be the :root braces
        expect(result.scan(/\{/).count).to eq(1)
        expect(result.scan(/\}/).count).to eq(1)
      end

      it 'sanitizes javascript: URLs' do
        malicious_data = {
          'color_scheme' => {
            'primary' => 'javascript:alert(1)'
          }
        }

        result = described_class.generate_theme_css(malicious_data)
        expect(result).not_to include('javascript:')
      end

      it 'sanitizes malicious property names' do
        malicious_data = {
          'color_scheme' => {
            'primary;<script>' => 'red'
          }
        }

        result = described_class.generate_theme_css(malicious_data)
        # Property name should be sanitized to only include valid characters
        expect(result).not_to include('<')
        expect(result).not_to include('>')
        # Semicolons in property names are removed
        expect(result).to include('--color-primaryscript: red') # Brackets removed, semicolon removed
      end

      it 'includes entries even if they contain only text after sanitization' do
        malicious_data = {
          'color_scheme' => {
            'primary' => '<script>alert(1)</script>' # Angle brackets removed, text remains
          }
        }

        result = described_class.generate_theme_css(malicious_data)
        # After removing angle brackets, we get 'scriptalert(1)/script'
        expect(result).to include(':root {')
        expect(result).to include('--color-primary:')
        # The dangerous characters are gone
        expect(result).not_to include('<')
        expect(result).not_to include('>')
      end
    end

    context 'with nil or empty theme data' do
      it 'returns empty string for nil' do
        expect(described_class.generate_theme_css(nil)).to eq('')
      end

      it 'returns empty :root block for empty hash' do
        expect(described_class.generate_theme_css({})).to eq(':root {  }')
      end

      it 'returns empty :root block when color_scheme is nil' do
        expect(described_class.generate_theme_css({ 'color_scheme' => nil })).to eq(':root {  }')
      end
    end

    context 'with mixed valid and invalid data' do
      it 'preserves valid entries and sanitizes invalid ones' do
        mixed_data = {
          'color_scheme' => {
            'primary' => '#3b82f6', # Valid
            'secondary' => 'red; </style><script>alert(1)</script>', # Malicious
            'accent' => '#f59e0b' # Valid
          }
        }

        result = described_class.generate_theme_css(mixed_data)
        expect(result).to include('--color-primary: #3b82f6')
        expect(result).to include('--color-accent: #f59e0b')
        expect(result).not_to include('<script>')
        expect(result).not_to include('</style>')
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebsiteTemplateService, type: :service do
  describe '.sanitize_css_value' do
    context 'basic functionality' do
      it 'returns empty string for blank input' do
        expect(described_class.sanitize_css_value('')).to eq('')
        expect(described_class.sanitize_css_value(nil)).to eq('')
        expect(described_class.sanitize_css_value('   ')).to eq('')
      end

      it 'preserves valid CSS values' do
        expect(described_class.sanitize_css_value('#ff0000')).to eq('#ff0000')
        expect(described_class.sanitize_css_value('blue')).to eq('blue')
        expect(described_class.sanitize_css_value('10px')).to eq('10px')
      end

      it 'strips whitespace' do
        expect(described_class.sanitize_css_value('  blue  ')).to eq('blue')
      end
    end

    context 'XSS protection' do
      it 'removes angle brackets' do
        result = described_class.sanitize_css_value('red</style><script>alert(1)</script>')
        expect(result).not_to include('<')
        expect(result).not_to include('>')
      end

      it 'removes curly braces to prevent CSS context escape' do
        result = described_class.sanitize_css_value('red; } body { display: none; }')
        expect(result).not_to include('{')
        expect(result).not_to include('}')
      end

      it 'removes quotes' do
        result = described_class.sanitize_css_value('red" onclick="alert(1)"')
        expect(result).not_to include('"')
        expect(result).not_to include("'")
      end

      it 'removes backslashes' do
        result = described_class.sanitize_css_value('red\\ </style>')
        expect(result).not_to include('\\')
      end
    end

    context 'dangerous pattern removal' do
      it 'removes javascript: URLs' do
        result = described_class.sanitize_css_value('url(javascript:alert(1))')
        expect(result).not_to include('javascript:')
      end

      it 'removes CSS expressions' do
        result = described_class.sanitize_css_value('expression(alert(1))')
        expect(result).not_to include('expression(')
      end

      it 'removes behavior property' do
        result = described_class.sanitize_css_value('behavior: url(xss.htc)')
        expect(result).not_to include('behavior:')
      end

      it 'removes vbscript: URLs' do
        result = described_class.sanitize_css_value('vbscript:msgbox(1)')
        expect(result).not_to include('vbscript:')
      end

      it 'removes @import' do
        result = described_class.sanitize_css_value('@import url(evil.css)')
        expect(result).not_to include('@import')
      end

      it 'removes onload event' do
        result = described_class.sanitize_css_value('onload: alert(1)')
        expect(result).not_to include('onload')
      end

      it 'removes onerror event' do
        result = described_class.sanitize_css_value('onerror: alert(1)')
        expect(result).not_to include('onerror')
      end
    end

    context 'length limitation' do
      it 'limits value to 500 characters to prevent DOS' do
        long_value = 'a' * 1000
        result = described_class.sanitize_css_value(long_value)
        expect(result.length).to eq(500)
      end
    end
  end

  describe '.sanitize_css_property_name' do
    it 'returns empty string for blank input' do
      expect(described_class.sanitize_css_property_name('')).to eq('')
      expect(described_class.sanitize_css_property_name(nil)).to eq('')
    end

    it 'preserves valid property names' do
      expect(described_class.sanitize_css_property_name('color')).to eq('color')
      expect(described_class.sanitize_css_property_name('background-color')).to eq('background-color')
    end

    it 'converts underscores to hyphens' do
      expect(described_class.sanitize_css_property_name('font_size')).to eq('font-size')
      expect(described_class.sanitize_css_property_name('line_height')).to eq('line-height')
    end

    it 'removes dangerous characters' do
      result = described_class.sanitize_css_property_name('color;}<script>alert(1)</script>')
      expect(result).not_to include(';')
      expect(result).not_to include('}')
      expect(result).not_to include('<')
      expect(result).not_to include('>')
    end

    it 'only allows alphanumeric, hyphens, and underscores' do
      result = described_class.sanitize_css_property_name('prop@name!test$value')
      expect(result).to eq('propnametestvalue')
    end
  end

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

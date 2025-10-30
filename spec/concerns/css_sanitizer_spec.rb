# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CssSanitizer do
  describe '.sanitize_css_value' do
    context 'with blank or nil values' do
      it 'returns empty string for nil' do
        expect(CssSanitizer.sanitize_css_value(nil)).to eq('')
      end

      it 'returns empty string for empty string' do
        expect(CssSanitizer.sanitize_css_value('')).to eq('')
      end

      it 'returns empty string for whitespace-only string' do
        expect(CssSanitizer.sanitize_css_value('   ')).to eq('')
      end
    end

    context 'with legitimate CSS values' do
      it 'preserves valid color values' do
        expect(CssSanitizer.sanitize_css_value('#ff0000')).to eq('#ff0000')
        expect(CssSanitizer.sanitize_css_value('rgb(255, 0, 0)')).to eq('rgb(255, 0, 0)')
        expect(CssSanitizer.sanitize_css_value('red')).to eq('red')
      end

      it 'preserves valid size values' do
        expect(CssSanitizer.sanitize_css_value('16px')).to eq('16px')
        expect(CssSanitizer.sanitize_css_value('1.5em')).to eq('1.5em')
        expect(CssSanitizer.sanitize_css_value('100%')).to eq('100%')
      end

      it 'preserves valid font names' do
        expect(CssSanitizer.sanitize_css_value('Arial')).to eq('Arial')
        expect(CssSanitizer.sanitize_css_value('Helvetica Neue')).to eq('Helvetica Neue')
      end

      it 'strips leading and trailing whitespace' do
        expect(CssSanitizer.sanitize_css_value('  #ff0000  ')).to eq('#ff0000')
      end
    end

    context 'XSS protection - dangerous characters' do
      it 'removes angle brackets' do
        expect(CssSanitizer.sanitize_css_value('<script>alert("xss")</script>')).to eq('scriptalert(xss)/script')
      end

      it 'removes curly braces to prevent context breakout' do
        expect(CssSanitizer.sanitize_css_value('red; } body { background: blue')).to eq('red;  body  background: blue')
      end

      it 'removes backslashes' do
        expect(CssSanitizer.sanitize_css_value('test\\value')).to eq('testvalue')
      end

      it 'removes single quotes' do
        expect(CssSanitizer.sanitize_css_value("test'value")).to eq('testvalue')
      end

      it 'removes double quotes' do
        expect(CssSanitizer.sanitize_css_value('test"value')).to eq('testvalue')
      end
    end

    context 'XSS protection - dangerous patterns' do
      it 'removes javascript: protocol' do
        expect(CssSanitizer.sanitize_css_value('javascript:alert(1)')).to eq('alert(1)')
        expect(CssSanitizer.sanitize_css_value('JAVASCRIPT:alert(1)')).to eq('alert(1)')
      end

      it 'removes expression() for IE exploits' do
        expect(CssSanitizer.sanitize_css_value('expression(alert(1))')).to eq('alert(1))')
        expect(CssSanitizer.sanitize_css_value('EXPRESSION (alert(1))')).to eq('alert(1))')
      end

      it 'removes behavior: for IE exploits' do
        expect(CssSanitizer.sanitize_css_value('behavior:url(xss.htc)')).to eq('url(xss.htc)')
        expect(CssSanitizer.sanitize_css_value('BEHAVIOR :url(xss.htc)')).to eq('url(xss.htc)')
      end

      it 'removes vbscript: protocol' do
        expect(CssSanitizer.sanitize_css_value('vbscript:msgbox')).to eq('msgbox')
        expect(CssSanitizer.sanitize_css_value('VBSCRIPT:msgbox')).to eq('msgbox')
      end

      it 'removes @import directives' do
        expect(CssSanitizer.sanitize_css_value('@import url(evil.css)')).to eq(' url(evil.css)')
        expect(CssSanitizer.sanitize_css_value('@IMPORT url(evil.css)')).to eq(' url(evil.css)')
      end

      it 'removes onload event handler' do
        expect(CssSanitizer.sanitize_css_value('onload=alert(1)')).to eq('=alert(1)')
        expect(CssSanitizer.sanitize_css_value('ONLOAD=alert(1)')).to eq('=alert(1)')
      end

      it 'removes onerror event handler' do
        expect(CssSanitizer.sanitize_css_value('onerror=alert(1)')).to eq('=alert(1)')
        expect(CssSanitizer.sanitize_css_value('ONERROR=alert(1)')).to eq('=alert(1)')
      end
    end

    context 'XSS protection - overlapping pattern attacks' do
      it 'handles overlapping javascript patterns' do
        # "javascjavascript:ript:" should be fully removed
        expect(CssSanitizer.sanitize_css_value('javascjavascript:ript:alert(1)')).to eq('alert(1)')
      end

      it 'handles overlapping expression patterns' do
        # "expresexpression(sion(" should be fully removed, leaving the closing parentheses
        expect(CssSanitizer.sanitize_css_value('expresexpression(sion(alert(1))')).to eq('alert(1))' )
      end

      it 'handles overlapping onerror patterns' do
        # "ononerrorerror" should be fully removed
        expect(CssSanitizer.sanitize_css_value('ononerrorerror=alert(1)')).to eq('=alert(1)')
      end

      it 'handles deeply nested overlapping patterns' do
        # Multiple layers of overlapping
        expect(CssSanitizer.sanitize_css_value('javajavascript:script:javascjavascript:ript:alert(1)')).to eq('alert(1)')
      end
    end

    context 'DoS protection' do
      it 'limits length to 500 characters' do
        long_value = 'a' * 1000
        result = CssSanitizer.sanitize_css_value(long_value)
        expect(result.length).to eq(500)
        expect(result).to eq('a' * 500)
      end

      it 'counts length after sanitization' do
        # After removing dangerous patterns, should still truncate
        dangerous_long = ('<script>' * 100) + ('a' * 500)
        result = CssSanitizer.sanitize_css_value(dangerous_long)
        expect(result.length).to eq(500)
      end
    end

    context 'edge cases' do
      it 'handles numeric values' do
        expect(CssSanitizer.sanitize_css_value(123)).to eq('123')
        expect(CssSanitizer.sanitize_css_value(45.67)).to eq('45.67')
      end

      it 'handles URL functions (after quotes removed)' do
        # Quotes will be removed but url() structure preserved
        expect(CssSanitizer.sanitize_css_value('url(image.png)')).to eq('url(image.png)')
      end

      it 'preserves CSS calc() function' do
        expect(CssSanitizer.sanitize_css_value('calc(100% - 20px)')).to eq('calc(100% - 20px)')
      end
    end
  end

  describe '.sanitize_css_property_name' do
    context 'with blank or nil values' do
      it 'returns empty string for nil' do
        expect(CssSanitizer.sanitize_css_property_name(nil)).to eq('')
      end

      it 'returns empty string for empty string' do
        expect(CssSanitizer.sanitize_css_property_name('')).to eq('')
      end

      it 'returns empty string for whitespace-only string' do
        expect(CssSanitizer.sanitize_css_property_name('   ')).to eq('')
      end
    end

    context 'with legitimate CSS property names' do
      it 'preserves valid property names' do
        expect(CssSanitizer.sanitize_css_property_name('color')).to eq('color')
        expect(CssSanitizer.sanitize_css_property_name('background-color')).to eq('background-color')
        expect(CssSanitizer.sanitize_css_property_name('font-size')).to eq('font-size')
      end

      it 'converts underscores to hyphens for CSS convention' do
        expect(CssSanitizer.sanitize_css_property_name('font_size')).to eq('font-size')
        expect(CssSanitizer.sanitize_css_property_name('background_color')).to eq('background-color')
        expect(CssSanitizer.sanitize_css_property_name('border_top_width')).to eq('border-top-width')
      end

      it 'preserves custom property names' do
        expect(CssSanitizer.sanitize_css_property_name('primary')).to eq('primary')
        expect(CssSanitizer.sanitize_css_property_name('heading-font')).to eq('heading-font')
      end
    end

    context 'XSS protection' do
      it 'removes special characters' do
        expect(CssSanitizer.sanitize_css_property_name('color<script>')).to eq('colorscript')
        expect(CssSanitizer.sanitize_css_property_name('bad;property')).to eq('badproperty')
        expect(CssSanitizer.sanitize_css_property_name('test:value')).to eq('testvalue')
      end

      it 'removes quotes' do
        expect(CssSanitizer.sanitize_css_property_name('color"bad')).to eq('colorbad')
        expect(CssSanitizer.sanitize_css_property_name("color'bad")).to eq('colorbad')
      end

      it 'removes braces' do
        expect(CssSanitizer.sanitize_css_property_name('color{}')).to eq('color')
      end

      it 'removes parentheses' do
        expect(CssSanitizer.sanitize_css_property_name('color()')).to eq('color')
      end
    end

    context 'edge cases' do
      it 'handles numeric inputs' do
        expect(CssSanitizer.sanitize_css_property_name(123)).to eq('123')
      end

      it 'handles mixed alphanumeric names' do
        expect(CssSanitizer.sanitize_css_property_name('color123')).to eq('color123')
        expect(CssSanitizer.sanitize_css_property_name('test-prop-2')).to eq('test-prop-2')
      end

      it 'handles symbols converted to strings' do
        expect(CssSanitizer.sanitize_css_property_name(:color)).to eq('color')
        expect(CssSanitizer.sanitize_css_property_name(:font_size)).to eq('font-size')
      end
    end
  end

  describe 'module usage patterns' do
    context 'as module methods' do
      it 'can be called as CssSanitizer.sanitize_css_value' do
        expect(CssSanitizer.sanitize_css_value('#ff0000')).to eq('#ff0000')
      end

      it 'can be called as CssSanitizer.sanitize_css_property_name' do
        expect(CssSanitizer.sanitize_css_property_name('color')).to eq('color')
      end
    end

    context 'as included methods' do
      let(:test_class) do
        Class.new do
          include CssSanitizer

          def test_sanitize_value(value)
            sanitize_css_value(value)
          end

          def test_sanitize_name(name)
            sanitize_css_property_name(name)
          end
        end
      end

      let(:test_instance) { test_class.new }

      it 'can be used as instance methods' do
        expect(test_instance.test_sanitize_value('#ff0000')).to eq('#ff0000')
        expect(test_instance.test_sanitize_name('color')).to eq('color')
      end
    end
  end
end

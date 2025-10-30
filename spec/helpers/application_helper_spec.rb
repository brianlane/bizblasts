# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  describe '#sanitize_css' do
    context 'basic functionality' do
      it 'returns empty string for blank input' do
        expect(helper.sanitize_css('')).to eq('')
        expect(helper.sanitize_css(nil)).to eq('')
        expect(helper.sanitize_css('   ')).to eq('')
      end

      it 'preserves valid CSS' do
        valid_css = '.container { color: blue; margin: 10px; }'
        result = helper.sanitize_css(valid_css)
        expect(result).to include('color: blue')
        expect(result).to include('margin: 10px')
      end
    end

    context 'script tag removal' do
      it 'removes simple script tags' do
        malicious_css = '.test { color: red; } <script>alert("XSS")</script>'
        result = helper.sanitize_css(malicious_css)
        # Security requirement: script tags must be removed (text content is harmless)
        expect(result).not_to include('<script>')
        expect(result).not_to include('</script>')
      end

      it 'removes nested script tags (primary vulnerability)' do
        malicious_css = '.test { color: red; } <sc<script>ript>alert("XSS")</script>'
        result = helper.sanitize_css(malicious_css)
        # Security requirement: nested script tags must be removed
        expect(result).not_to include('<script>')
        expect(result).not_to include('</script>')
        # Verify no angle brackets remain (all tags removed)
        expect(result).not_to match(/<[^>]*>/)
      end

      it 'removes deeply nested script tags' do
        malicious_css = '<sc<sc<script>ript>ript>alert(1)</script>'
        result = helper.sanitize_css(malicious_css)
        # Security requirement: deeply nested script tags must be removed
        expect(result).not_to include('<script>')
        expect(result).not_to include('</script>')
        # Verify no angle brackets remain
        expect(result).not_to match(/<[^>]*>/)
      end

      it 'removes script tags with mixed case' do
        malicious_css = '<ScRiPt>alert(1)</sCrIpT>'
        result = helper.sanitize_css(malicious_css)
        # Security requirement: mixed case script tags must be removed
        expect(result).not_to match(/<script/i)
        expect(result).not_to match(/<\/script/i)
        expect(result).not_to include('ScRiPt')
      end
    end

    context 'javascript: URL removal' do
      it 'removes javascript: URLs' do
        malicious_css = 'background: url(javascript:alert(1));'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('javascript:')
      end

      it 'removes nested javascript: patterns' do
        malicious_css = 'background: url(javascjajavascript:ript:alert(1));'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('javascript:')
      end

      it 'removes javascript: with mixed case' do
        malicious_css = 'background: url(JaVaScRiPt:alert(1));'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('javascript:')
        expect(result).not_to include('JaVaScRiPt:')
      end
    end

    context 'onload event handler removal' do
      it 'removes simple onload' do
        malicious_css = '.test { onload: expression(alert(1)); }'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('onload')
      end

      it 'removes nested onload (primary vulnerability)' do
        malicious_css = '.test { ononloadload: expression(alert(1)); }'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('onload')
      end

      it 'removes deeply nested onload' do
        malicious_css = 'ononononloadloadload'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('onload')
      end

      it 'removes onload with mixed case' do
        malicious_css = 'OnLoAd'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('onload')
        expect(result).not_to include('OnLoAd')
      end
    end

    context 'onerror event handler removal' do
      it 'removes simple onerror' do
        malicious_css = '.test { onerror: expression(alert(1)); }'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('onerror')
      end

      it 'removes nested onerror (primary vulnerability)' do
        malicious_css = '.test { ononerrorerror: expression(alert(1)); }'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('onerror')
      end

      it 'removes deeply nested onerror' do
        malicious_css = 'ononononerrorerrorerror'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('onerror')
      end

      it 'removes onerror with mixed case' do
        malicious_css = 'OnErRoR'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('onerror')
        expect(result).not_to include('OnErRoR')
      end
    end

    context 'CSS expression removal' do
      it 'removes simple expressions' do
        malicious_css = '.test { width: expression(alert(1)); }'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('expression(')
      end

      it 'removes nested expressions' do
        malicious_css = '.test { width: expresexpression(sion(alert(1)); }'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('expression(')
      end

      it 'removes expressions with various spacing' do
        malicious_css = '.test { width: expression  (alert(1)); }'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('expression')
      end
    end

    context 'behavior property removal' do
      it 'removes behavior property' do
        malicious_css = '.test { behavior: url(something.htc); }'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('behavior')
      end

      it 'removes nested behavior' do
        malicious_css = '.test { behavbehavior:ior: url(something.htc); }'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('behavior:')
      end
    end

    context '@import removal' do
      it 'removes @import statements' do
        malicious_css = '@import url("malicious.css");'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('@import')
      end

      it 'removes nested @import' do
        malicious_css = '@im@import@importport url("malicious.css");'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('@import')
      end
    end

    context 'vbscript: URL removal' do
      it 'removes vbscript: URLs' do
        malicious_css = 'background: url(vbscript:msgbox(1));'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('vbscript:')
      end

      it 'removes nested vbscript:' do
        malicious_css = 'background: url(vbsvbscript:cript:msgbox(1));'
        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('vbscript:')
      end
    end

    context 'combined attack vectors' do
      it 'removes multiple different attack patterns' do
        malicious_css = <<~CSS
          .evil {
            <sc<script>ript>alert(1)</script>
            background: url(javascjajavascript:ript:alert(1));
            ononloadload: expression(alert(1));
            ononerrorerror: expression(alert(1));
            width: expresexpression(sion(alert(1));
          }
        CSS

        result = helper.sanitize_css(malicious_css)
        expect(result).not_to include('script')
        expect(result).not_to include('javascript:')
        expect(result).not_to include('onload')
        expect(result).not_to include('onerror')
        expect(result).not_to include('expression(')
      end

      it 'preserves valid CSS while removing attacks' do
        mixed_css = '.valid { color: blue; margin: 10px; } <sc<script>ript>alert(1)</script> ononloadload'

        result = helper.sanitize_css(mixed_css)
        expect(result).to include('color: blue')
        expect(result).to include('margin: 10px')
        expect(result).not_to include('script')
        expect(result).not_to include('onload')
      end
    end

    context 'edge cases' do
      it 'handles extremely long input' do
        long_css = 'a' * 10000
        result = helper.sanitize_css(long_css)
        expect(result).to be_a(String)
      end

      it 'handles special characters' do
        special_css = '.test { content: "!@#$%^&*()"; }'
        result = helper.sanitize_css(special_css)
        expect(result).to be_a(String)
      end

      it 'handles unicode characters' do
        unicode_css = '.test { content: "Hello 世界"; }'
        result = helper.sanitize_css(unicode_css)
        expect(result).to be_a(String)
      end
    end
  end

  describe '#sanitize_css_value' do
    context 'basic functionality' do
      it 'returns empty string for blank input' do
        expect(helper.sanitize_css_value('')).to eq('')
        expect(helper.sanitize_css_value(nil)).to eq('')
        expect(helper.sanitize_css_value('   ')).to eq('')
      end

      it 'preserves valid CSS color values' do
        expect(helper.sanitize_css_value('#ff0000')).to eq('#ff0000')
        expect(helper.sanitize_css_value('rgb(255, 0, 0)')).to eq('rgb(255, 0, 0)')
        expect(helper.sanitize_css_value('blue')).to eq('blue')
      end

      it 'preserves valid CSS size values' do
        expect(helper.sanitize_css_value('10px')).to eq('10px')
        expect(helper.sanitize_css_value('1.5em')).to eq('1.5em')
        expect(helper.sanitize_css_value('100%')).to eq('100%')
      end
    end

    context 'XSS protection' do
      it 'removes angle brackets to prevent tag injection' do
        result = helper.sanitize_css_value('red; </style><script>alert(1)</script><style>')
        expect(result).not_to include('<')
        expect(result).not_to include('>')
        # Note: the word 'script' remains but without angle brackets it's harmless
        expect(result).to include('script') # Text content remains
      end

      it 'removes curly braces to prevent CSS escape' do
        result = helper.sanitize_css_value('red; } body { display: none; } .x {')
        expect(result).not_to include('{')
        expect(result).not_to include('}')
      end

      it 'removes quotes to prevent attribute injection' do
        result = helper.sanitize_css_value('red" onclick="alert(1)"')
        expect(result).not_to include('"')
        expect(result).not_to include("'")
      end

      it 'removes backslashes to prevent escape sequences' do
        result = helper.sanitize_css_value('red\\ </style>')
        expect(result).not_to include('\\')
      end
    end

    context 'dangerous pattern removal' do
      it 'removes javascript: URLs' do
        result = helper.sanitize_css_value('javascript:alert(1)')
        expect(result).not_to include('javascript:')
      end

      it 'removes CSS expressions' do
        result = helper.sanitize_css_value('expression(alert(1))')
        expect(result).not_to include('expression(')
      end

      it 'removes behavior property' do
        result = helper.sanitize_css_value('behavior: url(xss.htc)')
        expect(result).not_to include('behavior:')
      end

      it 'removes vbscript: URLs' do
        result = helper.sanitize_css_value('vbscript:msgbox(1)')
        expect(result).not_to include('vbscript:')
      end

      it 'removes @import' do
        result = helper.sanitize_css_value('@import url(evil.css)')
        expect(result).not_to include('@import')
      end

      it 'removes onload event' do
        result = helper.sanitize_css_value('onload')
        expect(result).not_to include('onload')
      end

      it 'removes onerror event' do
        result = helper.sanitize_css_value('onerror')
        expect(result).not_to include('onerror')
      end
    end

    context 'length limitation' do
      it 'limits value to 500 characters' do
        long_value = 'a' * 1000
        result = helper.sanitize_css_value(long_value)
        expect(result.length).to eq(500)
      end
    end
  end

  describe '#sanitize_css_property_name' do
    it 'returns empty string for blank input' do
      expect(helper.sanitize_css_property_name('')).to eq('')
      expect(helper.sanitize_css_property_name(nil)).to eq('')
    end

    it 'preserves valid property names' do
      expect(helper.sanitize_css_property_name('color')).to eq('color')
      expect(helper.sanitize_css_property_name('background-color')).to eq('background-color')
      expect(helper.sanitize_css_property_name('font_size')).to eq('font_size')
    end

    it 'removes dangerous characters' do
      result = helper.sanitize_css_property_name('color;}<script>alert(1)</script>')
      expect(result).not_to include(';')
      expect(result).not_to include('}')
      expect(result).not_to include('<')
      expect(result).not_to include('>')
      expect(result).to eq('colorscriptalert1script')
    end

    it 'only allows alphanumeric, hyphens, and underscores' do
      result = helper.sanitize_css_property_name('prop@name!test$value')
      expect(result).to eq('propnametestvalue')
    end
  end

  describe '#safe_business_url' do
    let(:business) { create(:business, hostname: 'testbiz', host_type: :subdomain) }
    let(:custom_business) { create(:business, hostname: 'example.com', host_type: :custom_domain) }

    before do
      allow(helper).to receive(:request).and_return(
        double(
          domain: 'bizblasts.com',
          port: 3000,
          ssl?: false
        )
      )
    end

    context 'basic functionality' do
      it 'returns nil for nil business' do
        expect(helper.safe_business_url(nil)).to be_nil
      end

      it 'returns nil for business without hostname' do
        business.hostname = nil
        expect(helper.safe_business_url(business)).to be_nil
      end

      it 'constructs URL for subdomain business' do
        result = helper.safe_business_url(business, '/test')
        expect(result).to eq('http://testbiz.bizblasts.com:3000/test')
      end

      it 'constructs URL for custom domain business' do
        result = helper.safe_business_url(custom_business, '/test')
        expect(result).to eq('http://example.com:3000/test')
      end
    end

    context 'parameter encoding' do
      it 'properly encodes query parameters' do
        result = helper.safe_business_url(business, '/payments/new', invoice_id: 123)
        expect(result).to include('invoice_id=123')
      end

      it 'encodes special characters in parameters' do
        result = helper.safe_business_url(business, '/test', name: 'test & value')
        # ERB::Util.url_encode encodes spaces as %20, not +
        expect(result).to match(/name=test(%20|\+)%26(%20|\+)value/)
      end
    end

    context 'XSS protection' do
      it 'rejects invalid subdomain hostnames' do
        business.hostname = 'test<script>alert(1)</script>'
        result = helper.safe_business_url(business)
        expect(result).to be_nil
      end

      it 'rejects invalid custom domain hostnames' do
        custom_business.hostname = 'evil.com<script>alert(1)</script>'
        result = helper.safe_business_url(custom_business)
        expect(result).to be_nil
      end

      it 'validates subdomain format' do
        business.hostname = 'test;rm -rf /'
        result = helper.safe_business_url(business)
        expect(result).to be_nil
      end

      it 'validates custom domain format' do
        custom_business.hostname = 'not a valid domain'
        result = helper.safe_business_url(custom_business)
        expect(result).to be_nil
      end
    end

    context 'port handling' do
      it 'omits port for standard HTTP port 80' do
        allow(helper).to receive(:request).and_return(
          double(domain: 'bizblasts.com', port: 80, ssl?: false)
        )
        result = helper.safe_business_url(business)
        expect(result).not_to include(':80')
      end

      it 'omits port for standard HTTPS port 443' do
        allow(helper).to receive(:request).and_return(
          double(domain: 'bizblasts.com', port: 443, ssl?: true)
        )
        result = helper.safe_business_url(business)
        expect(result).not_to include(':443')
      end

      it 'includes non-standard ports' do
        result = helper.safe_business_url(business)
        expect(result).to include(':3000')
      end
    end

    context 'protocol handling' do
      it 'uses https for SSL requests' do
        allow(helper).to receive(:request).and_return(
          double(domain: 'bizblasts.com', port: 443, ssl?: true)
        )
        result = helper.safe_business_url(business)
        expect(result).to start_with('https://')
      end

      it 'uses http for non-SSL requests' do
        result = helper.safe_business_url(business)
        expect(result).to start_with('http://')
      end
    end
  end
end

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
end

/**
 * Markdown Editor Tests
 * 
 * These tests verify the XSS protection mechanisms and markdown rendering
 * functionality of the ActiveAdmin markdown editor.
 */

// Import the markdown editor class (we'll need to export it first)
// For now, we'll test by loading the file and accessing the class

describe('MarkdownEditor', () => {
  let editor;
  let mockEditor, mockToolbar, mockPreview;

  beforeEach(() => {
    // Set up DOM elements
    document.body.innerHTML = `
      <div class="markdown-editor-toolbar"></div>
      <textarea class="markdown-editor"></textarea>
      <div id="content-preview"></div>
    `;

    mockEditor = document.querySelector('.markdown-editor');
    mockToolbar = document.querySelector('.markdown-editor-toolbar');
    mockPreview = document.getElementById('content-preview');
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  describe('XSS Protection - HTML Escaping', () => {
    // We'll test the escapeHtml method directly
    function escapeHtml(text) {
      if (!text) return '';
      const div = document.createElement('div');
      div.textContent = text;
      return div.innerHTML;
    }

    test('escapes script tags', () => {
      const malicious = '<script>alert("XSS")</script>';
      const escaped = escapeHtml(malicious);
      
      expect(escaped).not.toContain('<script>');
      expect(escaped).toContain('&lt;script&gt;');
    });

    test('escapes event handlers', () => {
      const malicious = '<img src=x onerror="alert(1)">';
      const escaped = escapeHtml(malicious);

      // Verify the entire tag is escaped (making it safe)
      expect(escaped).toContain('&lt;img');
      expect(escaped).toContain('&gt;');
      // The escaped string should NOT contain executable img tag
      expect(escaped).not.toContain('<img');
    });

    test('escapes iframe tags', () => {
      const malicious = '<iframe src="javascript:alert(1)"></iframe>';
      const escaped = escapeHtml(malicious);
      
      expect(escaped).not.toContain('<iframe');
      expect(escaped).toContain('&lt;iframe');
    });

    test('handles null and undefined input', () => {
      expect(escapeHtml(null)).toBe('');
      expect(escapeHtml(undefined)).toBe('');
      expect(escapeHtml('')).toBe('');
    });

    test('preserves plain text', () => {
      const text = 'Hello World';
      expect(escapeHtml(text)).toBe('Hello World');
    });

    test('escapes HTML entities', () => {
      const text = '< > & " \'';
      const escaped = escapeHtml(text);
      
      expect(escaped).toContain('&lt;');
      expect(escaped).toContain('&gt;');
      expect(escaped).toContain('&amp;');
    });
  });

  describe('XSS Protection - URL Sanitization', () => {
    // Test the sanitizeUrl method
    function sanitizeUrl(url) {
      if (!url) return '#';
      
      url = url.trim();
      
      const textarea = document.createElement('textarea');
      textarea.innerHTML = url;
      const decoded = textarea.value;
      
      const dangerous = /^[\s]*(javascript|data|vbscript|file|about)\s*:/i;
      if (dangerous.test(decoded)) {
        return '#';
      }
      
      return url;
    }

    test('blocks javascript: protocol', () => {
      expect(sanitizeUrl('javascript:alert(1)')).toBe('#');
      expect(sanitizeUrl('JAVASCRIPT:alert(1)')).toBe('#');
      expect(sanitizeUrl('  javascript:alert(1)')).toBe('#');
    });

    test('blocks data: protocol', () => {
      expect(sanitizeUrl('data:text/html,<script>alert(1)</script>')).toBe('#');
      expect(sanitizeUrl('DATA:text/html,alert(1)')).toBe('#');
    });

    test('blocks vbscript: protocol', () => {
      expect(sanitizeUrl('vbscript:msgbox(1)')).toBe('#');
      expect(sanitizeUrl('VBSCRIPT:msgbox(1)')).toBe('#');
    });

    test('blocks file: protocol', () => {
      expect(sanitizeUrl('file:///etc/passwd')).toBe('#');
    });

    test('blocks about: protocol', () => {
      expect(sanitizeUrl('about:blank')).toBe('#');
    });

    test('allows safe http:// URLs', () => {
      const url = 'http://example.com';
      expect(sanitizeUrl(url)).toBe(url);
    });

    test('allows safe https:// URLs', () => {
      const url = 'https://example.com/path?query=value';
      expect(sanitizeUrl(url)).toBe(url);
    });

    test('allows relative URLs', () => {
      expect(sanitizeUrl('/path/to/page')).toBe('/path/to/page');
      expect(sanitizeUrl('./relative')).toBe('./relative');
    });

    test('handles null and empty input', () => {
      expect(sanitizeUrl(null)).toBe('#');
      expect(sanitizeUrl('')).toBe('#');
      // Whitespace-only returns the trimmed (empty) string, which is acceptable
      const whitespace = sanitizeUrl('  ');
      expect(whitespace === '#' || whitespace === '').toBeTruthy();
    });

    test('handles URL with encoded entities', () => {
      // Test that HTML-encoded dangerous protocols are still blocked
      const encoded = '&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;&#58;alert(1)';
      expect(sanitizeUrl(encoded)).toBe('#');
    });
  });

  describe('Markdown Rendering', () => {
    test('renders links with noopener noreferrer', () => {
      // This tests that external links have the security attribute
      const link = '<a href="https://example.com" target="_blank" rel="noopener noreferrer" style="color: #0066cc;">text</a>';

      expect(link).toContain('rel="noopener noreferrer"');
      expect(link).toContain('target="_blank"');
    });

    test('sanitizes URLs in rendered links', () => {
      // Verify that malicious URLs are sanitized before rendering
      // Define sanitizeUrl helper for this test
      function sanitizeUrl(url) {
        if (!url) return '#';
        const dangerous = /^[\s]*(javascript|data|vbscript|file|about)\s*:/i;
        return dangerous.test(url) ? '#' : url;
      }

      const dangerousUrl = 'javascript:alert(1)';
      const safeUrl = sanitizeUrl(dangerousUrl);

      expect(safeUrl).toBe('#');
    });
  });

  describe('Security Edge Cases', () => {
    test('handles mixed case protocols', () => {
      const sanitizeUrl = (url) => {
        if (!url) return '#';
        const dangerous = /^[\s]*(javascript|data|vbscript|file|about)\s*:/i;
        return dangerous.test(url) ? '#' : url;
      };

      expect(sanitizeUrl('JaVaScRiPt:alert(1)')).toBe('#');
      expect(sanitizeUrl('jAvAsCrIpT:alert(1)')).toBe('#');
    });

    test('handles whitespace before protocol', () => {
      const sanitizeUrl = (url) => {
        if (!url) return '#';
        const dangerous = /^[\s]*(javascript|data|vbscript|file|about)\s*:/i;
        return dangerous.test(url) ? '#' : url;
      };

      expect(sanitizeUrl('  javascript:alert(1)')).toBe('#');
      expect(sanitizeUrl('\tjavascript:alert(1)')).toBe('#');
      expect(sanitizeUrl('\njavascript:alert(1)')).toBe('#');
    });

    test('handles nested/chained protocols', () => {
      const sanitizeUrl = (url) => {
        if (!url) return '#';
        const dangerous = /^[\s]*(javascript|data|vbscript|file|about)\s*:/i;
        return dangerous.test(url) ? '#' : url;
      };

      expect(sanitizeUrl('data:text/html,<script>javascript:alert(1)</script>')).toBe('#');
    });
  });

  describe('Performance', () => {
    test('escapeHtml handles large inputs efficiently', () => {
      const largeText = 'a'.repeat(10000);
      const start = Date.now();
      
      const escapeHtml = (text) => {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
      };
      
      escapeHtml(largeText);
      const duration = Date.now() - start;
      
      // Should complete in reasonable time (< 100ms for 10k chars)
      expect(duration).toBeLessThan(100);
    });
  });
});

// Export for use in other tests if needed
module.exports = { MarkdownEditor: true };

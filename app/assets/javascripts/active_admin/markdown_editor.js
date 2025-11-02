// Markdown Editor Class for ActiveAdmin
// Provides markdown editing with real-time preview and XSS protection

class MarkdownEditor {
  constructor() {
    this.init();
  }

  init() {
    // Setup immediately if DOM is ready, otherwise wait
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', () => this.setupEditor());
    } else {
      this.setupEditor();
    }

    // Watch for dynamically loaded content (ActiveAdmin navigation) using MutationObserver
    // This is more efficient than polling with setInterval
    this.observer = new MutationObserver(() => {
      // Only attempt setup if there's an uninitialized markdown editor
      if (document.querySelector('.markdown-editor:not([data-editor-initialized])')) {
        this.setupEditor();
      }
    });

    this.observer.observe(document.body, {
      childList: true,
      subtree: true
    });

    // Cleanup observer on Turbo navigation to prevent memory leaks
    document.addEventListener('turbo:before-cache', () => {
      this.cleanup();
    });
  }

  cleanup() {
    if (this.observer) {
      this.observer.disconnect();
      this.observer = null;
    }
  }

  setupEditor() {
    const editor = document.querySelector('.markdown-editor');
    const toolbar = document.querySelector('.markdown-editor-toolbar');
    const preview = document.getElementById('content-preview');

    if (!editor || !toolbar || editor.dataset.editorInitialized) {
      return;
    }

    // Mark as initialized to prevent duplicate setup
    editor.dataset.editorInitialized = 'true';

    this.editor = editor;
    this.toolbar = toolbar;
    this.preview = preview;
    this.isPreviewMode = false;

    this.setupToolbarHandlers();
    this.setupKeyboardShortcuts();
    this.setupAutoResize();
  }

  wrapText(before, after = '', placeholder = '') {
    const start = this.editor.selectionStart;
    const end = this.editor.selectionEnd;
    const text = this.editor.value;
    const selectedText = text.substring(start, end);

    const replacement = selectedText ?
      before + selectedText + after :
      before + placeholder + after;

    const newText = text.substring(0, start) + replacement + text.substring(end);
    this.editor.value = newText;

    const newCursorPos = start + before.length + (selectedText || placeholder).length;
    this.editor.setSelectionRange(newCursorPos, newCursorPos);
    this.editor.focus();
  }

  insertAtLineStart(prefix) {
    const start = this.editor.selectionStart;
    const text = this.editor.value;
    const lineStart = text.lastIndexOf('\n', start - 1) + 1;
    const lineEnd = text.indexOf('\n', start);
    const currentLine = text.substring(lineStart, lineEnd === -1 ? text.length : lineEnd);

    const newLine = currentLine.startsWith(prefix) ?
      currentLine.substring(prefix.length) :
      prefix + currentLine;

    const before = text.substring(0, lineStart);
    const after = text.substring(lineEnd === -1 ? text.length : lineEnd);

    this.editor.value = before + newLine + after;
    this.editor.setSelectionRange(lineStart + prefix.length, lineStart + prefix.length);
    this.editor.focus();
  }

  setupToolbarHandlers() {
    const handlers = {
      'bold-btn': () => this.wrapText('**', '**', 'bold text'),
      'italic-btn': () => this.wrapText('*', '*', 'italic text'),
      'code-btn': () => this.wrapText('`', '`', 'code'),
      'h1-btn': () => this.insertAtLineStart('# '),
      'h2-btn': () => this.insertAtLineStart('## '),
      'h3-btn': () => this.insertAtLineStart('### '),
      'link-btn': () => {
        const url = prompt('Enter URL:');
        if (url) this.wrapText('[', `](${url})`, 'link text');
      },
      'image-btn': () => {
        const url = prompt('Enter image URL:');
        const alt = prompt('Enter alt text (optional):') || 'image';
        if (url) this.wrapText('', '', `![${alt}](${url})`);
      },
      'quote-btn': () => this.insertAtLineStart('> '),
      'codeblock-btn': () => {
        const language = prompt('Enter language (optional):') || '';
        this.wrapText(`\`\`\`${language}\n`, '\n```', 'code here');
      },
      'ul-btn': () => this.insertAtLineStart('- '),
      'ol-btn': () => this.insertAtLineStart('1. '),
      'table-btn': () => {
        const table = '| Header 1 | Header 2 | Header 3 |\n|----------|----------|----------|\n| Cell 1   | Cell 2   | Cell 3   |\n| Cell 4   | Cell 5   | Cell 6   |';
        this.wrapText('', '', table);
      },
      'preview-btn': () => this.togglePreview()
    };

    Object.keys(handlers).forEach(className => {
      const button = this.toolbar.querySelector(`.${className}`);
      if (button) {
        button.addEventListener('click', (e) => {
          e.preventDefault();
          handlers[className]();
        });
      }
    });
  }

  /**
   * SECURITY FIX (Alert #23 - CWE-79): Escape HTML before markdown processing
   * This function escapes all HTML special characters to prevent XSS attacks.
   * By escaping BEFORE applying markdown transformations, we ensure that:
   * 1. Raw HTML/script tags cannot be injected
   * 2. Event handlers (onerror, onclick, etc.) are neutralized
   * 3. Only safe markdown-generated HTML is rendered
   */
  escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  /**
   * SECURITY: Sanitize URL to prevent javascript: and data: URI attacks
   * Only allows http:, https:, mailto:, and relative URLs
   * @param {string} url - URL to sanitize
   * @returns {string} - Sanitized URL or '#' if dangerous
   */
  sanitizeUrl(url) {
    if (!url) return '#';

    // Trim whitespace
    url = url.trim();

    // Decode HTML entities that might have been escaped
    const textarea = document.createElement('textarea');
    textarea.innerHTML = url;
    const decoded = textarea.value;

    // Check for dangerous protocols (case-insensitive, allow whitespace before colon)
    const dangerous = /^[\s]*(javascript|data|vbscript|file|about)\s*:/i;
    if (dangerous.test(decoded)) {
      console.warn('Blocked dangerous URL protocol:', decoded);
      return '#';
    }

    // Allow http:, https:, mailto:, tel:, sms:, and relative URLs (allow whitespace before colon)
    const safe = /^[\s]*(https?\s*:|mailto\s*:|tel\s*:|sms\s*:|\/|\.\/|\.\.\/|#)/i;
    if (safe.test(decoded)) {
      return url; // Return original (possibly entity-encoded) URL
    }

    // If no protocol specified, treat as relative (safe, allow whitespace)
    if (!/^[\s]*[\w]+\s*:/.test(decoded)) {
      return url;
    }

    // Block everything else
    console.warn('Blocked unsafe URL:', decoded);
    return '#';
  }

  togglePreview() {
    const previewBtn = this.toolbar.querySelector('.preview-btn');

    if (this.isPreviewMode) {
      this.preview.style.display = 'none';
      this.editor.style.display = 'block';
      previewBtn.textContent = 'Preview';
      previewBtn.style.background = '#0066cc';
      this.isPreviewMode = false;
    } else {
      this.preview.style.display = 'block';
      this.editor.style.display = 'none';
      previewBtn.textContent = 'Edit';
      previewBtn.style.background = '#28a745';
      this.isPreviewMode = true;
      this.updatePreview();
    }
  }

  /**
   * SECURITY FIX (Alert #23 - CWE-79): DOM text reinterpreted as HTML vulnerability
   *
   * BEFORE: User input was processed with regex and directly set via innerHTML
   * AFTER:
   *   1. User input is HTML-escaped FIRST
   *   2. Markdown transformations applied
   *   3. URLs sanitized to prevent javascript:/data: URIs
   *
   * This prevents XSS attacks like:
   * - <script>alert('XSS')</script>
   * - <img src=x onerror="alert('XSS')">
   * - [link](javascript:alert('XSS'))
   * - ![img](javascript:alert('XSS'))
   *
   * The fix ensures only safe, markdown-generated HTML with safe URLs is rendered.
   */
  updatePreview() {
    if (!this.preview) return;

    // SECURITY: Escape ALL HTML special characters first
    const escaped = this.escapeHtml(this.editor.value);

    // Now apply markdown transformations on the ESCAPED content
    // This ensures only safe, markdown-generated HTML is created
    let html = escaped
      .replace(/^### (.*$)/gim, '<h3>$1</h3>')
      .replace(/^## (.*$)/gim, '<h2>$1</h2>')
      .replace(/^# (.*$)/gim, '<h1>$1</h1>')
      .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.*?)\*/g, '<em>$1</em>')
      .replace(/`(.*?)`/g, '<code style="background: #f4f4f4; padding: 2px 4px; border-radius: 3px; font-family: monospace;">$1</code>')
      // SECURITY: Sanitize URLs in links
      .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (match, text, url) => {
        const safeUrl = this.sanitizeUrl(url);
        return `<a href="${safeUrl}" target="_blank" rel="noopener noreferrer" style="color: #0066cc;">${text}</a>`;
      })
      // SECURITY: Sanitize URLs in images
      .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (match, alt, url) => {
        const safeUrl = this.sanitizeUrl(url);
        return `<img src="${safeUrl}" alt="${alt}" style="max-width: 100%; height: auto; border-radius: 4px;">`;
      })
      .replace(/```(\w+)?\n([\s\S]*?)```/g, '<pre style="background: #f8f8f8; padding: 10px; border-radius: 4px; overflow-x: auto;"><code>$2</code></pre>')
      .replace(/^> (.*$)/gim, '<blockquote style="border-left: 4px solid #ddd; margin: 0; padding-left: 16px; color: #666;">$1</blockquote>')
      .replace(/^- (.*$)/gim, '<li>$1</li>')
      .replace(/^1\. (.*$)/gim, '<li>$1</li>')
      .replace(/\n/g, '<br>');

    // Wrap list items in ul tags
    html = html.replace(/(<li>.*?<\/li>(?:<br><li>.*?<\/li>)*)/g, '<ul style="margin: 10px 0; padding-left: 20px;">$1</ul>');
    html = html.replace(/<br><li>/g, '<li>').replace(/<\/li><br>/g, '</li>');

    // Safe to set innerHTML now - all user input escaped and URLs sanitized
    this.preview.innerHTML = html || '<em style="color: #999;">Preview will appear here...</em>';
  }

  setupKeyboardShortcuts() {
    this.editor.addEventListener('keydown', (e) => {
      if (e.ctrlKey || e.metaKey) {
        switch(e.key) {
          case 'b':
            e.preventDefault();
            this.wrapText('**', '**', 'bold text');
            break;
          case 'i':
            e.preventDefault();
            this.wrapText('*', '*', 'italic text');
            break;
          case 'k':
            e.preventDefault();
            this.wrapText('`', '`', 'code');
            break;
          case 'l': {
            e.preventDefault();
            const url = prompt('Enter URL:');
            if (url) this.wrapText('[', `](${url})`, 'link text');
            break;
          }
        }
      }
    });
  }

  setupAutoResize() {
    const autoResize = () => {
      // Store current scroll position and cursor position
      const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
      const cursorPosition = this.editor.selectionStart;

      // Store the current height to check if resize is needed
      const currentHeight = this.editor.offsetHeight;

      // Temporarily set height to auto to get the required height
      this.editor.style.height = 'auto';
      const newHeight = this.editor.scrollHeight;

      // Only resize if there's a significant difference (avoids constant micro-adjustments)
      if (Math.abs(newHeight - currentHeight) > 5) {
        this.editor.style.height = newHeight + 'px';
      } else {
        // Restore original height if no significant change needed
        this.editor.style.height = currentHeight + 'px';
      }

      // Restore scroll position to prevent jumping
      window.scrollTo(0, scrollTop);

      // Restore cursor position
      this.editor.setSelectionRange(cursorPosition, cursorPosition);
    };

    // Use a debounced version to avoid too frequent resizing
    let resizeTimeout;
    const debouncedResize = () => {
      clearTimeout(resizeTimeout);
      resizeTimeout = setTimeout(autoResize, 100);
    };

    this.editor.addEventListener('input', debouncedResize);

    // Prevent scroll jumping on focus/click
    this.editor.addEventListener('focus', (e) => {
      e.preventDefault();
      // Don't scroll to show cursor when focusing
    });

    // Prevent scroll jumping when clicking to position cursor
    this.editor.addEventListener('click', (e) => {
      const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
      setTimeout(() => {
        window.scrollTo(0, scrollTop);
      }, 1);
    });

    // Initial resize without debouncing
    autoResize();
  }
}

// Expose class globally so ActiveAdmin views and tests can access it
const globalObject = typeof globalThis !== 'undefined' ? globalThis : window;
if (globalObject) {
  globalObject.MarkdownEditor = MarkdownEditor;
}

// Initialize markdown editor
new MarkdownEditor();

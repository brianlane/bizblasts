# Markdown Preview Content Security Policy

## Overview

The markdown preview functionality in ActiveAdmin has enhanced security through Content Security Policy (CSP) headers. This document explains the security measures in place and how to use them.

## Security Layers

### 1. Client-Side XSS Protection (JavaScript)
- **HTML Escaping**: All user input is escaped using `textContent` before rendering
- **URL Sanitization**: Dangerous protocols (javascript:, data:, vbscript:) are blocked
- **Safe Rendering**: Markdown is converted to HTML with escaped content

### 2. Server-Side Sanitization (Ruby)
- **MarkdownSanitizable Concern**: Sanitizes markdown fields before database storage
- **Sanitize Gem**: Uses `RELAXED` config to allow safe HTML while blocking XSS
- **Change Detection**: Only sanitizes fields that have been modified

### 3. Content Security Policy Headers
- **MarkdownPreviewSecurity Concern**: Adds stricter CSP for markdown editor pages
- **Script Restrictions**: Blocks inline event handlers and external script loading
- **Nonce-Based Scripts**: Allows only trusted scripts with cryptographic nonces
- **Object Blocking**: Prevents object/embed tags that could load plugins

## Using CSP with Markdown Preview

### For ActiveAdmin Resources

Include the concern and apply CSP to edit/new actions:

```ruby
ActiveAdmin.register Article do
  include MarkdownPreviewSecurity

  before_action :set_markdown_preview_csp, only: [:new, :edit]

  form do |f|
    f.inputs do
      # Regular markdown field - CSP protects the preview
      f.input :content, as: :text, input_html: {
        class: 'markdown-editor',
        data: { preview_target: 'content-preview' }
      }
      f.li class: 'markdown-preview' do
        content_tag :div, '', id: 'content-preview'
      end
    end
    f.actions
  end
end
```

### For Regular Controllers

```ruby
class ArticlesController < ApplicationController
  include MarkdownPreviewSecurity

  before_action :set_markdown_preview_csp, only: [:new, :edit]

  def new
    @article = Article.new
    # CSP headers automatically applied
  end

  def edit
    @article = Article.find(params[:id])
    # CSP headers automatically applied
  end
end
```

### In View Templates

If you need to include inline scripts with CSP nonces:

```erb
<script nonce="<%= csp_nonce %>">
  // Your trusted inline script here
  console.log('This script is allowed by CSP');
</script>
```

## CSP Policy Details

The markdown preview CSP includes these directives:

- **default-src 'self'**: Only load resources from same origin by default
- **script-src 'self' 'nonce-{random}'**: Only allow same-origin scripts and nonce-protected inline scripts
- **style-src 'self' 'unsafe-inline'**: Allow inline styles (needed for markdown rendering)
- **img-src 'self' https: data: blob:**: Allow images from various sources
- **object-src 'none'**: Block plugins and embedded objects
- **base-uri 'self'**: Prevent base tag injection attacks

## Testing CSP

### Check CSP Headers

```bash
curl -I https://your-app.com/admin/articles/new | grep -i content-security
```

### Browser Console

Modern browsers show CSP violations in the console:
```
Refused to execute inline script because it violates the following Content Security Policy directive...
```

### Monitor Violations

Enable CSP reporting in `config/initializers/content_security_policy.rb`:

```ruby
policy.report_uri "/csp-violation-report-endpoint"
```

## Security Benefits

1. **XSS Prevention**: Multiple layers prevent script injection
   - Client-side escaping catches malicious input
   - Server-side sanitization ensures clean database storage
   - CSP blocks execution even if escaping fails

2. **Defense in Depth**: Three independent security layers
   - JavaScript sanitization (first line of defense)
   - Ruby sanitization (database protection)
   - CSP headers (browser-level enforcement)

3. **Clickjacking Protection**: frame-src directive prevents embedding
4. **Plugin Protection**: object-src blocks Flash, Java, and other plugins
5. **Base Tag Protection**: base-uri prevents URL hijacking

## Troubleshooting

### CSP Blocks Legitimate Script

If CSP blocks a script you need:

1. **Add nonce to inline script**:
   ```erb
   <script nonce="<%= csp_nonce %>">...</script>
   ```

2. **Move script to external file**:
   - Scripts in `app/assets/javascripts/` are allowed
   - Scripts loaded from CDNs need to be whitelisted

3. **Whitelist specific domain**:
   ```ruby
   def build_markdown_preview_csp(nonce)
     # Add trusted domain to script-src
     "script-src 'self' 'nonce-#{nonce}' https://trusted-cdn.com"
   end
   ```

### CSP Too Restrictive

If CSP causes issues in production:

1. **Use report-only mode** during testing:
   ```ruby
   response.headers['Content-Security-Policy-Report-Only'] = build_markdown_preview_csp(@csp_nonce)
   ```

2. **Review browser console** for violations
3. **Adjust policy** based on legitimate needs
4. **Re-enable enforcement** after validation

## Related Documentation

- [XSS Protection Tests](../spec/javascript/active_admin/markdown_editor_spec.js)
- [Server-Side Sanitization](../app/models/concerns/markdown_sanitizable.rb)
- [Markdown Editor Implementation](../app/assets/javascripts/active_admin/markdown_editor.js)
- [Rails CSP Guide](https://guides.rubyonrails.org/security.html#content-security-policy-header)

## Maintenance

### Updating CSP Policy

When adding new features:

1. Test with strict CSP first
2. Monitor for violations
3. Adjust policy only if necessary
4. Document any changes
5. Update this guide

### Security Audits

Regular security checks:

- [ ] Review CSP violation reports
- [ ] Test XSS payloads in markdown editor
- [ ] Verify sanitization with edge cases
- [ ] Check for new OWASP top 10 issues
- [ ] Update dependencies (Sanitize gem)

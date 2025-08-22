# Custom Domain Setup FAQ

This guide provides step-by-step instructions for setting up CNAME records with popular domain registrars for BizBlasts Premium businesses.

## Quick Reference

**Your CNAME Configuration:**
- **Name/Host:** `@` (for root domain) or `www` (for www subdomain)
- **Type:** `CNAME`
- **Value/Target:** `bizblasts.onrender.com`
- **TTL:** `Auto` or `300` (5 minutes)

⚠️ **Important:** Remove any existing A or AAAA records for your domain before adding the CNAME record.

---

## Registrar-Specific Instructions

### GoDaddy

1. **Log into GoDaddy:** Go to [godaddy.com](https://godaddy.com) and sign in
2. **Access DNS Management:** 
   - Click "My Products" → "DNS" next to your domain
   - Or go to "Domains" → select your domain → "DNS"
3. **Add CNAME Record:**
   - Click "Add" button
   - **Type:** Select "CNAME"
   - **Name:** Enter `@` (for root domain) or `www`
   - **Value:** Enter `bizblasts.onrender.com`
   - **TTL:** Leave as "1 hour" or set to "Custom: 300 seconds"
4. **Remove Conflicting Records:**
   - Delete any existing A records for `@` or `www`
   - Delete any existing AAAA records for `@` or `www`
5. **Save Changes:** Click "Save"

**GoDaddy Notes:**
- Changes typically take 10-15 minutes to propagate
- You may need to wait up to 1 hour for full global propagation

### Namecheap

1. **Log into Namecheap:** Go to [namecheap.com](https://namecheap.com) and sign in
2. **Access Domain List:** Click "Domain List" in the left sidebar
3. **Manage DNS:**
   - Find your domain and click "Manage"
   - Click "Advanced DNS" tab
4. **Add CNAME Record:**
   - Click "Add New Record"
   - **Type:** Select "CNAME Record"
   - **Host:** Enter `@` (for root domain) or `www`
   - **Value:** Enter `bizblasts.onrender.com`
   - **TTL:** Select "5 min" or "Automatic"
5. **Remove Conflicting Records:**
   - Delete any A records with Host `@` or `www`
   - Delete any AAAA records with Host `@` or `www`
6. **Save Changes:** Click the green checkmark

**Namecheap Notes:**
- Changes usually propagate within 5-30 minutes
- Namecheap automatically adds a trailing dot to CNAME values

### Cloudflare

1. **Log into Cloudflare:** Go to [cloudflare.com](https://cloudflare.com) and sign in
2. **Select Your Domain:** Click on your domain from the dashboard
3. **Access DNS Settings:** Click "DNS" in the top menu
4. **Add CNAME Record:**
   - Click "Add record"
   - **Type:** Select "CNAME"
   - **Name:** Enter `@` (for root domain) or `www`
   - **Target:** Enter `bizblasts.onrender.com`
   - **Proxy status:** Toggle OFF (gray cloud) - **Very Important!**
   - **TTL:** Select "Auto" or "5 minutes"
5. **Remove Conflicting Records:**
   - Delete any A records with Name `@` or `www`
   - Delete any AAAA records with Name `@` or `www`
6. **Save:** Click "Save"

**Cloudflare Notes:**
- **Critical:** Ensure proxy is OFF (gray cloud) for CNAME records
- Changes propagate very quickly (1-5 minutes) due to Cloudflare's global network
- Cloudflare requires you to change nameservers to theirs for full functionality

### Google Domains (Google Cloud DNS)

1. **Log into Google Domains:** Go to [domains.google.com](https://domains.google.com)
2. **Select Your Domain:** Click on your domain name
3. **Access DNS Settings:**
   - Click "DNS" in the left menu
   - Scroll to "Custom records"
4. **Add CNAME Record:**
   - Click "Manage custom records"
   - **Host name:** Enter `@` or `www`
   - **Type:** Select "CNAME"
   - **TTL:** Enter `300` (5 minutes)
   - **Data:** Enter `bizblasts.onrender.com`
5. **Remove Conflicting Records:**
   - Delete any A records for `@` or `www`
   - Delete any AAAA records for `@` or `www`
6. **Save:** Click "Save"

**Google Domains Notes:**
- Google automatically appends your domain to the host name
- Changes typically take 10-15 minutes to propagate globally
- Google Domains provides detailed propagation status

### Hover

1. **Log into Hover:** Go to [hover.com](https://hover.com) and sign in
2. **Select Your Domain:** Click on your domain from the domain list
3. **Access DNS Settings:** Click "DNS" tab
4. **Add CNAME Record:**
   - Click "Add New"
   - **Type:** Select "CNAME"
   - **Hostname:** Enter `@` or `www`
   - **Target Host:** Enter `bizblasts.onrender.com`
5. **Remove Conflicting Records:**
   - Delete any A records for `@` or `www`
6. **Save Changes:** Changes are saved automatically

**Hover Notes:**
- Clean, simple interface
- Changes usually propagate within 15-30 minutes

### Other Registrars

**For registrars not listed above, follow these general steps:**

1. Log into your domain registrar's control panel
2. Find "DNS Management," "DNS Settings," or "Name Servers" section
3. Look for options to "Add Record" or "Add DNS Record"
4. Create a new CNAME record with:
   - **Name/Host/Subdomain:** `@` (root) or `www`
   - **Type:** `CNAME`
   - **Value/Target/Destination:** `bizblasts.onrender.com`
   - **TTL:** `300` seconds (5 minutes) or lowest available
5. Remove any conflicting A or AAAA records
6. Save your changes

---

## Common Issues & Troubleshooting

### ❌ "CNAME record not found"

**Possible Causes:**
- Record not saved properly
- DNS changes haven't propagated yet
- Conflicting A/AAAA records still present

**Solutions:**
1. **Double-check your record:**
   - Verify the target is exactly `bizblasts.onrender.com`
   - Ensure no extra spaces or characters
   - Confirm you're editing the correct domain

2. **Wait for propagation:**
   - DNS changes can take 5 minutes to 2 hours
   - Test from different devices/networks
   - Use DNS checker tools (see below)

3. **Remove conflicting records:**
   - Delete all A records for your domain/subdomain
   - Delete all AAAA records for your domain/subdomain
   - Some registrars require this before allowing CNAME

### ❌ "CNAME points to wrong target"

**Possible Causes:**
- Typo in target domain
- Registrar added extra characters
- Old cached DNS records

**Solutions:**
1. **Verify target domain:**
   - Must be exactly: `bizblasts.onrender.com`
   - No `www.` prefix
   - No `https://` prefix
   - Some registrars add trailing dot automatically (this is normal)

2. **Clear DNS cache:**
   - Restart your router/modem
   - Flush DNS on your computer
   - Try from different network (mobile data)

### ❌ "Domain setup timeout"

**Possible Causes:**
- DNS propagation taking longer than expected
- ISP DNS cache not updated
- Registrar-specific delays

**Solutions:**
1. **Check DNS propagation:**
   - Use tools like [whatsmydns.net](https://whatsmydns.net)
   - Search for your domain and select "CNAME"
   - Green checkmarks = propagated, red X = not yet

2. **Contact support:**
   - Forward your setup email to support
   - Include screenshots of your DNS settings
   - We can manually verify and restart monitoring

### ❌ "SSL certificate issues"

**Possible Causes:**
- Domain recently activated (SSL takes time)
- Mixed HTTP/HTTPS content
- Browser cache

**Solutions:**
1. **Wait for SSL provisioning:**
   - SSL certificates can take up to 24 hours
   - Domain will show "Not Secure" initially
   - BizBlasts handles this automatically

2. **Force HTTPS:**
   - Always use `https://yourdomain.com`
   - Clear browser cache and cookies
   - Try incognito/private browsing mode

---

## DNS Verification Tools

Use these free tools to check if your CNAME record is configured correctly:

### Online DNS Checkers
- **[whatsmydns.net](https://whatsmydns.net)** - Global DNS propagation checker
- **[dnschecker.org](https://dnschecker.org)** - Multi-location DNS lookup
- **[mxtoolbox.com](https://mxtoolbox.com/CNAMELookup.aspx)** - Professional DNS tools

### Command Line Tools
```bash
# Check CNAME record (Mac/Linux)
nslookup -type=CNAME yourdomain.com

# Check CNAME record (Windows)
nslookup -type=CNAME yourdomain.com

# Check with specific DNS server
nslookup -type=CNAME yourdomain.com 8.8.8.8
```

**Expected Result:**
```
yourdomain.com canonical name = bizblasts.onrender.com
```

---

## Timeline Expectations

### Normal Setup Timeline
- **0-5 minutes:** CNAME record saved at registrar
- **5-15 minutes:** DNS propagation begins
- **15-30 minutes:** BizBlasts detects CNAME (monitoring every 5 minutes)
- **30-60 minutes:** Domain activated if all checks pass
- **1-24 hours:** SSL certificate fully provisioned

### Factors That Affect Speed
- **Registrar speed:** Some are faster than others
- **TTL settings:** Lower TTL = faster propagation
- **DNS cache:** ISP and browser caching can delay updates
- **Geographic location:** Propagation varies by region

---

## Support & Contact

### Need Help?
- **Email:** Forward your original setup instructions to [support@bizblasts.com](mailto:support@bizblasts.com)
- **Include:** Screenshots of your DNS settings and any error messages
- **Response Time:** We typically respond within 24 hours

### Emergency Support
If your domain setup is urgent:
1. Reply to your original setup email with "URGENT" in the subject
2. Include your business name and domain
3. We can manually verify and activate your domain

### Self-Service Options
- Check our [help documentation](https://docs.bizblasts.com)
- Use DNS verification tools listed above
- Try the setup from a different network/device

---

## Advanced Configuration

### Using www vs Root Domain

**Root Domain Setup (example.com):**
- **Host:** `@`
- **Visitors type:** `example.com` → redirects to your BizBlasts site

**WWW Subdomain Setup (www.example.com):**
- **Host:** `www`
- **Visitors type:** `www.example.com` → redirects to your BizBlasts site

**Both (Recommended):**
Set up both records so visitors can reach you either way.

### Email Considerations

⚠️ **Important:** CNAME records for your root domain may affect email delivery.

**If you use email with your domain:**
1. Set up CNAME for `www` subdomain only
2. Keep A records for root domain and email
3. Use `www.yourdomain.com` for your BizBlasts site

**Consult your email provider** before making DNS changes if you have existing email services.

### Multiple Subdomains

Currently, BizBlasts supports one domain per business. Contact support if you need multiple subdomain configurations.

---

This FAQ covers the most common scenarios and registrars. If your situation isn't covered here, don't hesitate to contact our support team!
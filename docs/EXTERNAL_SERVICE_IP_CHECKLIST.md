# External Service IP Allowlist Configuration Checklist

## **🎯 Purpose**
Quick reference checklist for updating external service IP allowlists during Render's IP address transition (October 27 - December 1, 2025).

---

## **📋 New Render IP Addresses**
Add these IPs to all external service allowlists:
- `3.134.238.14`
- `3.129.111.228`
- `52.15.118.168`
- `74.228.58.8/24`

**⚠️ IMPORTANT:** Do NOT remove old IPs until after December 1, 2025!

---

## **🔧 Service Configuration Steps**

### **1. Stripe**
**Priority:** 🔴 CRITICAL - Payment processing
**Dashboard:** [https://dashboard.stripe.com](https://dashboard.stripe.com)

**Steps:**
- [ ] Login to Stripe Dashboard
- [ ] Navigate to **Settings** → **Webhooks**
- [ ] Check if IP allowlisting is configured
- [ ] If configured, click **Configure allowlist**
- [ ] Add new Render IP addresses
- [ ] Save configuration
- [ ] Test webhook delivery: `rails render:test_webhooks`

**Test Command:**
```bash
rails render:check_external_apis
# Look for "Stripe API................... ✅ PASS"
```

---

### **2. Twilio**
**Priority:** 🔴 CRITICAL - SMS functionality
**Console:** [https://console.twilio.com](https://console.twilio.com)

**Steps:**
- [ ] Login to Twilio Console
- [ ] Navigate to **Settings** → **General**
- [ ] Check **IP Access Control Lists**
- [ ] If restrictions exist, add new Render IPs
- [ ] Test SMS functionality: `SmsService.send_message('+1234567890', 'test')`

**Test Commands:**
```bash
# Check API connectivity
rails render:check_external_apis

# Send test SMS (in Rails console)
rails console
> SmsService.send_message('+15555551234', 'IP transition test')
```

---

### **3. Resend Email**
**Priority:** 🟡 HIGH - Email delivery
**Dashboard:** [https://resend.com/dashboard](https://resend.com/dashboard)

**Steps:**
- [ ] Login to Resend Dashboard
- [ ] Navigate to **Settings** → **Security**
- [ ] Check for **IP Allowlist** settings
- [ ] If configured, add new Render IP addresses
- [ ] Test email delivery

**Test Command:**
```bash
# Check API connectivity
rails render:check_external_apis

# Send test email (in Rails console)
rails console
> AdminMailer.test_email('test@example.com').deliver_now
```

---

### **4. AWS S3**
**Priority:** 🟡 MEDIUM - File storage
**Console:** [https://console.aws.amazon.com/s3/](https://console.aws.amazon.com/s3/)

**Steps:**
- [ ] Login to AWS Console
- [ ] Navigate to **S3** → **Buckets** → Select your bucket
- [ ] Check **Permissions** → **Bucket Policy**
- [ ] Look for IP-based conditions in JSON policy
- [ ] If found, add new Render IP addresses to IP arrays
- [ ] Check **IAM** → **Policies** for IP conditions
- [ ] Test file upload functionality

**Test Commands:**
```bash
# Check S3 connectivity
rails render:check_external_apis

# Test file upload (in Rails console)
rails console
> ActiveStorage::Blob.create_and_upload!(io: StringIO.new("test"), filename: "test.txt")
```

---

### **5. Google Cloud (Places API)**
**Priority:** 🟡 MEDIUM - Business search
**Console:** [https://console.cloud.google.com](https://console.cloud.google.com)

**Steps:**
- [ ] Login to Google Cloud Console
- [ ] Navigate to **APIs & Services** → **Credentials**
- [ ] Click on your **API Key**
- [ ] Check **API restrictions** section
- [ ] If IP restrictions exist, add new Render IPs
- [ ] Test Places API functionality

**Test Command:**
```bash
# Check Google Places API connectivity
rails render:check_external_apis

# Test Places search (in Rails console)
rails console
> GooglePlacesSearchService.search_businesses('coffee shop', 'New York')
```

---

### **6. Microsoft Graph (if configured)**
**Priority:** 🟢 LOW - Calendar integration
**Portal:** [https://portal.azure.com](https://portal.azure.com)

**Steps:**
- [ ] Login to Azure Portal
- [ ] Navigate to **Azure Active Directory** → **App registrations**
- [ ] Select your application
- [ ] Check **Conditional Access** policies
- [ ] Look for IP-based restrictions
- [ ] Add new Render IP addresses if configured

---

## **🧪 Testing Protocol**

### **Pre-Change Baseline Test**
Run before October 27, 2025:
```bash
# Test all external API connectivity
rails render:check_external_apis

# Test webhook accessibility
rails render:test_webhooks

# Monitor for 24 hours to establish baseline
rails render:monitor_api_failures
```

### **Post-Change Verification**
Run after October 27, 2025:
```bash
# Immediate connectivity test
rails render:check_external_apis

# Test core functionality
rails console
> # Test payment processing
> # Test SMS sending
> # Test email delivery
> # Test file uploads

# Monitor for issues
tail -f log/production.log | grep "IP allowlist\|AUTHENTICATION ERROR\|PERMISSION ERROR"
```

### **Ongoing Monitoring**
Set up cron job to run every 15 minutes:
```bash
# Add to crontab
*/15 * * * * cd /path/to/bizblasts && rails render:monitor_api_failures
```

---

## **🚨 Emergency Procedures**

### **If Services Start Failing After October 27**

1. **Check Application Logs:**
   ```bash
   tail -f log/production.log | grep "AUTHENTICATION ERROR\|PERMISSION ERROR\|IP allowlist"
   ```

2. **Verify IP Configuration:**
   ```bash
   rails render:check_external_apis
   ```

3. **Quick Fix - Add IPs to Failing Service:**
   - Find the failing service from logs
   - Login to that service's dashboard
   - Add all Render IP addresses immediately
   - Re-test functionality

4. **Emergency Contacts:**
   - Stripe Support: [https://support.stripe.com](https://support.stripe.com)
   - Twilio Support: [https://support.twilio.com](https://support.twilio.com)
   - Render Support: [https://render.com/support](https://render.com/support)

---

## **📊 Success Criteria**

Configuration is successful when:
- [ ] `rails render:check_external_apis` shows all services ✅ PASS
- [ ] No increase in 403/401 errors in application logs
- [ ] SMS delivery rates remain normal
- [ ] Email delivery continues working
- [ ] Payment processing works normally
- [ ] File uploads function correctly

---

## **🗓️ Timeline Reminders**

- **October 27, 2025:** Add new IPs to all services
- **October 27-December 1:** Monitor closely, keep both IP sets active
- **December 2, 2025:** Remove old IP addresses from allowlists

---

**Last Updated:** October 2, 2025
**Next Review:** December 2, 2025
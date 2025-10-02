# Render IP Address Change - Implementation TODO

## **🎯 Overview**

Render is updating their outbound IP addresses on **October 27, 2025**. This document outlines all required changes to ensure BizBlasts continues to function properly with external services.

## **📊 Audit Results Summary**

**External API Services Found in Codebase:**
- ✅ **Stripe API** - `/app/services/stripe_service.rb`
- ✅ **Twilio API** - `/app/services/sms_service.rb`
- ✅ **Resend Email API** - `/config/initializers/resend.rb`
- ✅ **AWS S3** - `/config/storage.yml`
- ✅ **Google Places API** - `/app/services/google_places_search_service.rb`
- ✅ **Domain Health Checker** - `/app/services/domain_health_checker.rb`
- ✅ **Render API** - `/app/services/render_domain_service.rb`

**Hardcoded IP Found:**
- ⚠️ **Render Apex IP** in `/app/services/cname_dns_checker.rb:12`

**New Render IP Addresses:**
- `3.134.238.14`
- `3.129.111.228`
- `52.15.118.168`
- `74.228.58.8/24`
- `74.228.58.8/24`

**Old IP Addresses (retire after December 1, 2025):**
- `52.41.36.82`
- `54.191.253.12`
- `44.240.322.3`

---

## **🔧 Implementation Tasks**

### **1. CRITICAL - Code Fix for Hardcoded IP**

**File:** `/app/services/cname_dns_checker.rb`
**Line:** 12
**Current:** `RENDER_APEX_IP = '216.24.57.1'`

**Tasks:**
- [ ] Contact Render support to confirm if apex IP addresses are changing
- [ ] Determine if `216.24.57.1` needs to be updated to new apex IP
- [ ] Update `RENDER_APEX_IP` constant if Render provides new apex IP
- [ ] Test CNAME verification functionality after update
- [ ] Create regression test for apex IP verification

---

### **2. External Service IP Allowlist Updates**

#### **2.1 Stripe Dashboard Configuration**
**Priority:** HIGH - Critical for payment processing

**Tasks:**
- [ ] Login to [Stripe Dashboard](https://dashboard.stripe.com) → Settings → Webhooks
- [ ] Check if IP allowlisting is configured for webhook endpoints
- [ ] If configured, add new Render IP ranges:
  - `3.134.238.14`
  - `3.129.111.228`
  - `52.15.118.168`
  - `74.228.58.8/24`
- [ ] Test webhook delivery to `/webhooks/stripe` endpoint
- [ ] Verify payment processing still works
- [ ] Schedule removal of old IPs after December 1, 2025

#### **2.2 Twilio Console Configuration**
**Priority:** HIGH - Critical for SMS functionality

**Tasks:**
- [ ] Login to [Twilio Console](https://console.twilio.com) → Settings → IP Access Control Lists
- [ ] Check for existing IP restrictions on messaging service
- [ ] If restrictions exist, add new Render IP ranges
- [ ] Test SMS delivery functionality via `SmsService.send_message`
- [ ] Test webhook delivery to `/webhooks/twilio` endpoints
- [ ] Verify SMS delivery receipts still work

#### **2.3 AWS S3 Configuration**
**Priority:** MEDIUM - For file uploads

**Tasks:**
- [ ] Review S3 bucket policies for IP-based restrictions
- [ ] Check IAM policies for IP condition statements
- [ ] Update any IP-based access controls with new Render ranges
- [ ] Test file upload functionality via Active Storage
- [ ] Test file download/serving functionality
- [ ] Verify image processing pipeline still works

#### **2.4 Google Cloud Console**
**Priority:** MEDIUM - For Places API integration

**Tasks:**
- [ ] Login to [Google Cloud Console](https://console.cloud.google.com) → APIs & Services → Credentials
- [ ] Review API key restrictions for Places API
- [ ] Check if IP restrictions are configured
- [ ] If configured, update with new Render IP ranges
- [ ] Test Google Places integration via `GooglePlacesSearchService`
- [ ] Verify business search functionality

#### **2.5 Resend Email Service**
**Priority:** HIGH - Critical for email delivery

**Tasks:**
- [ ] Login to [Resend Dashboard](https://resend.com/dashboard)
- [ ] Check for IP allowlist settings in account configuration
- [ ] If configured, update with new Render IP ranges
- [ ] Test email delivery functionality
- [ ] Verify admin notification emails work
- [ ] Test business registration email delivery

---

### **3. Application Monitoring & Alerting**

#### **3.1 Enhanced Logging**
**Tasks:**
- [ ] Add debug logging to `StripeService` for API call failures
- [ ] Add debug logging to `SmsService` for Twilio API failures
- [ ] Add debug logging to `GooglePlacesSearchService` for API failures
- [ ] Add debug logging to `DomainHealthChecker` for HTTP failures
- [ ] Add debug logging to `RenderDomainService` for API failures

#### **3.2 Health Check Enhancements**
**Tasks:**
- [ ] Create rake task `render:check_external_apis` to test connectivity
- [ ] Add monitoring alerts for 403/401 API authentication failures
- [ ] Create dashboard to track external service connectivity metrics
- [ ] Set up alerts for webhook delivery failure spikes
- [ ] Monitor SMS/email delivery success rates

---

### **4. Testing & Validation**

#### **4.1 Pre-Change Testing Checklist**
**Before October 27, 2025:**
- [ ] Document current external service configurations
- [ ] Test all external API integrations work correctly
- [ ] Verify webhook endpoints are accessible
- [ ] Confirm SMS and email delivery works
- [ ] Test file upload/download functionality

#### **4.2 Post-Change Testing Checklist**
**After October 27, 2025:**
- [ ] Stripe payment processing and webhook delivery
- [ ] Twilio SMS sending and delivery receipt webhooks
- [ ] Email delivery via Resend
- [ ] File uploads/downloads to AWS S3
- [ ] Google Places API search functionality
- [ ] Custom domain health checks
- [ ] Render API domain management calls
- [ ] CNAME DNS verification (if apex IP changed)

#### **4.3 Monitoring During Transition**
**October 27 - December 1, 2025:**
- [ ] Monitor application logs for 403/401 errors
- [ ] Track webhook delivery failure rates
- [ ] Monitor SMS/email delivery rates
- [ ] Alert on external API connectivity issues
- [ ] Daily health checks of all integrations

---

### **5. Documentation & Knowledge Management**

#### **5.1 Documentation Updates**
**Tasks:**
- [ ] Document all external service IP allowlist configurations
- [ ] Create runbook for future IP address changes
- [ ] Document testing procedures for each integration
- [ ] Update architecture diagrams to show external dependencies
- [ ] Create troubleshooting guide for API connectivity issues

#### **5.2 Team Communication**
**Tasks:**
- [ ] Notify development team of upcoming changes
- [ ] Schedule maintenance window if needed
- [ ] Create rollback plan in case of issues
- [ ] Document emergency contacts for each external service

---

## **📅 Implementation Timeline**

### **Phase 1: Preparation (October 1-26, 2025)**
- [ ] Complete external service allowlist audits
- [ ] Set up enhanced monitoring and alerts
- [ ] Prepare updated configurations
- [ ] Test current functionality baseline
- [ ] Create rollback procedures

### **Phase 2: Add New IPs (October 27, 2025)**
- [ ] Add new Render IP ranges to all services **in the morning**
- [ ] Keep existing IPs active - **DO NOT REMOVE**
- [ ] Execute comprehensive testing suite
- [ ] Monitor for 24-48 hours continuously
- [ ] Document any issues encountered

### **Phase 3: Cleanup (December 2, 2025)**
- [ ] Remove old Render IP ranges from allowlists
- [ ] Update hardcoded IP in `cname_dns_checker.rb` if needed
- [ ] Final integration testing
- [ ] Update documentation with final configurations
- [ ] Archive this implementation guide

---

## **🚨 Critical Warnings**

1. **DO NOT remove old IPs until after December 1, 2025**
2. **Test thoroughly after adding new IPs on October 27**
3. **Keep both IP sets active during transition period**
4. **Monitor application logs closely during transition**
5. **Have rollback plan ready in case of issues**

---

## **📞 Emergency Contacts**

**If issues arise during implementation:**
- Stripe Support: [https://support.stripe.com](https://support.stripe.com)
- Twilio Support: [https://support.twilio.com](https://support.twilio.com)
- Render Support: [https://render.com/support](https://render.com/support)
- AWS Support: Via AWS Console
- Google Cloud Support: Via Google Cloud Console

---

## **✅ Success Criteria**

The implementation is successful when:
- [ ] All external API integrations work normally
- [ ] Webhook delivery rates remain at normal levels
- [ ] SMS and email delivery continue functioning
- [ ] File uploads/downloads work normally
- [ ] No increase in 403/401 API errors
- [ ] All monitoring shows green status

---

**Last Updated:** October 2, 2025
**Owner:** Development Team
**Review Date:** December 2, 2025
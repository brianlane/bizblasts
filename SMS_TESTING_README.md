# SMS Testing Scripts for Production

This directory contains Ruby scripts for testing SMS functionality in production with phone number `+16026866672`.

## Prerequisites

Before running these scripts, ensure:

1. **Environment Variables are Set:**
   ```bash
   ENABLE_SMS=true
   TWILIO_ACCOUNT_SID=your_account_sid
   TWILIO_AUTH_TOKEN=your_auth_token
   TWILIO_PHONE_NUMBER=your_twilio_number
   ```

2. **Customer Exists:**
   - A customer record must exist with phone number `+16026866672`
   - The customer must belong to a premium business with SMS enabled

3. **Production Access:**
   - You have access to the production Rails console
   - Twilio webhooks are configured to point to your production server

## Scripts Overview

### 1. `test_sms_production.rb` - Main SMS Test Script

**Purpose:** Comprehensive SMS functionality test that sends a real SMS message.

**Usage:**
```bash
# On production server
RAILS_ENV=production bundle exec rails runner test_sms_production.rb
```

**What it does:**
- ✅ Checks SMS configuration (Twilio credentials, global settings)
- ✅ Finds customer with the specified phone number
- ✅ Verifies business SMS capabilities
- ✅ Checks customer SMS preferences
- ✅ Reviews recent SMS message history
- ✅ Tests SMS template rendering
- ✅ **Sends a real test SMS message**
- ✅ Verifies message was logged in database

**Output:**
Detailed step-by-step output showing configuration status and test results.

**Warning:** This script **WILL SEND A REAL SMS** to the phone number!

---

### 2. `check_sms_webhook_status.rb` - Webhook Status Checker

**Purpose:** Check the current status of SMS opt-in/opt-out and view message history.

**Usage:**
```bash
# On production server
RAILS_ENV=production bundle exec rails runner check_sms_webhook_status.rb
```

**What it does:**
- ✅ Shows customer information and current opt-in status
- ✅ Displays recent SMS messages (last 10, both sent and received)
- ✅ Lists opt-in invitations
- ✅ Shows business-specific opt-outs
- ✅ Summarizes customer's SMS receiving capabilities

**Use this:**
- After replying to SMS to verify webhook processing worked
- To check if a customer is opted in or out
- To review SMS message history
- To debug webhook issues

---

### 3. `simulate_sms_webhook.rb` - Webhook Simulator

**Purpose:** Manually simulate webhook processing without waiting for actual SMS replies.

**Usage:**
```bash
# Simulate opt-in
RAILS_ENV=production bundle exec rails runner simulate_sms_webhook.rb YES

# Simulate opt-out
RAILS_ENV=production bundle exec rails runner simulate_sms_webhook.rb STOP

# Simulate re-opt-in
RAILS_ENV=production bundle exec rails runner simulate_sms_webhook.rb START

# Simulate help request
RAILS_ENV=production bundle exec rails runner simulate_sms_webhook.rb HELP
```

**What it does:**
- ✅ Simulates customer SMS replies (YES, STOP, START, HELP)
- ✅ Processes opt-in/opt-out logic
- ✅ Updates customer opt-in status
- ✅ Sends confirmation SMS messages
- ✅ Shows before/after opt-in status

**Valid commands:**
- `YES`, `Y` - Opt customer into SMS
- `STOP`, `UNSUBSCRIBE` - Opt customer out of SMS
- `START`, `UNSTOP` - Re-opt customer into SMS
- `HELP` - Send help message (no status change)

---

## Testing Workflow

### Full End-to-End Test

1. **Run the main test script:**
   ```bash
   RAILS_ENV=production bundle exec rails runner test_sms_production.rb
   ```
   - This sends a real SMS to your phone
   - Check that you receive the SMS

2. **Reply to the SMS on your phone:**
   - Reply `YES` to test opt-in webhook
   - Reply `STOP` to test opt-out webhook
   - Reply `HELP` to test help message
   - Reply `START` to test re-opt-in

3. **Check webhook processing:**
   ```bash
   RAILS_ENV=production bundle exec rails runner check_sms_webhook_status.rb
   ```
   - Verify your reply was received and processed
   - Check that opt-in/opt-out status changed correctly

### Testing Without Sending SMS

If you want to test the webhook logic without actually sending/receiving SMS:

```bash
# Simulate customer opting in
RAILS_ENV=production bundle exec rails runner simulate_sms_webhook.rb YES

# Check the result
RAILS_ENV=production bundle exec rails runner check_sms_webhook_status.rb

# Simulate customer opting out
RAILS_ENV=production bundle exec rails runner simulate_sms_webhook.rb STOP

# Check again
RAILS_ENV=production bundle exec rails runner check_sms_webhook_status.rb
```

---

## Troubleshooting

### SMS Not Sending

**Check:**
1. Environment variables are set correctly
2. Global SMS is enabled (`ENABLE_SMS=true`)
3. Twilio credentials are valid
4. Business tier is `premium`
5. Business `sms_enabled` is `true`
6. Customer has valid phone number

**Debug:**
```bash
# Check configuration
RAILS_ENV=production bundle exec rails runner test_sms_production.rb
```

### Webhook Not Processing

**Check:**
1. Twilio webhook URL is configured correctly
2. Webhook URL is accessible from internet
3. URL format: `https://yourdomain.com/webhooks/twilio/sms`
4. Webhook method is set to `POST`
5. Check Rails logs for incoming webhook requests

**Debug:**
```bash
# Monitor logs
tail -f log/production.log | grep -i twilio

# Check recent messages
RAILS_ENV=production bundle exec rails runner check_sms_webhook_status.rb

# Manually simulate webhook
RAILS_ENV=production bundle exec rails runner simulate_sms_webhook.rb YES
```

### Customer Not Found

If customer doesn't exist, create one:

```ruby
# In production Rails console
business = Business.where(tier: 'premium', sms_enabled: true).first
customer = TenantCustomer.create!(
  business: business,
  first_name: 'Brian',
  last_name: 'Test',
  email: 'brian.test@example.com',
  phone: '+16026866672',
  phone_opt_in: true,
  phone_opt_in_at: Time.current
)
```

---

## Expected Behavior

### When you reply `YES`:
- Customer `phone_opt_in` → `true`
- Customer `phone_opt_in_at` → current timestamp
- Pending SMS invitations marked as responded
- Confirmation SMS sent: "You're now subscribed..."

### When you reply `STOP`:
- Customer `phone_opt_in` → `false`
- Customer `phone_opt_out_at` → current timestamp
- Business opt-out record created
- Confirmation SMS sent: "You have been unsubscribed..."

### When you reply `START`:
- Customer `phone_opt_in` → `true`
- Customer `phone_opt_in_at` → current timestamp
- Business opt-out record removed
- Confirmation SMS sent: "You have been re-subscribed..."

### When you reply `HELP`:
- No opt-in status change
- Help SMS sent with subscription info

---

## Quick Reference

```bash
# Send test SMS
RAILS_ENV=production bundle exec rails runner test_sms_production.rb

# Check status
RAILS_ENV=production bundle exec rails runner check_sms_webhook_status.rb

# Simulate opt-in
RAILS_ENV=production bundle exec rails runner simulate_sms_webhook.rb YES

# Simulate opt-out
RAILS_ENV=production bundle exec rails runner simulate_sms_webhook.rb STOP

# View logs
tail -f log/production.log | grep -i sms
```

---

## Safety Notes

⚠️ **IMPORTANT:**
- These scripts run in **PRODUCTION** environment
- `test_sms_production.rb` **WILL SEND REAL SMS** messages (costs money)
- `simulate_sms_webhook.rb` **WILL SEND REAL SMS** confirmations
- Only `check_sms_webhook_status.rb` is read-only (safe to run anytime)
- All scripts modify production database records
- Use responsibly and verify actions before running

---

## Support

If you encounter issues:

1. Check the output of each script for error messages
2. Review Twilio logs at https://console.twilio.com
3. Check Rails production logs
4. Verify environment variables are set
5. Ensure customer and business records are configured correctly

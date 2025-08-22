# CNAME Custom Domain Implementation

This document details the complete implementation of the CNAME custom domain feature for BizBlasts Premium tier businesses.

## Overview

The CNAME custom domain feature allows Premium tier businesses to connect their own domains (e.g., `mybusiness.com`) to their BizBlasts sites using CNAME DNS records pointing to `bizblasts.onrender.com`.

## Architecture Components

### Database Schema

**New columns added to `businesses` table:**

```ruby
# Migration: 20250821171908_add_cname_fields_to_businesses.rb
cname_setup_email_sent_at: datetime        # When setup instructions were emailed
cname_monitoring_active: boolean, default: false  # Whether DNS monitoring is active
cname_check_attempts: integer, default: 0         # Number of DNS checks performed
render_domain_added: boolean, default: false      # Whether domain was added to Render

# Indexes for performance
index :cname_monitoring_active
index :status  # For domain status filtering
```

**New status enum values:**

```ruby
enum :status, {
  active: 'active', 
  inactive: 'inactive', 
  suspended: 'suspended',
  cname_pending: 'cname_pending',        # Domain setup initiated, waiting for DNS
  cname_monitoring: 'cname_monitoring',  # Actively checking DNS every 5 minutes
  cname_active: 'cname_active',          # Domain verified and active
  cname_timeout: 'cname_timeout'         # DNS verification timed out
}
```

### Service Layer

#### 1. RenderDomainService
Handles integration with Render.com Custom Domain API.

**Key Methods:**
- `add_domain(domain_name)` - Add domain to Render service
- `verify_domain(domain_id)` - Trigger domain verification
- `list_domains()` - List all domains for the service
- `remove_domain(domain_id)` - Remove domain from service
- `domain_status(domain_name)` - Check domain existence and verification status

**Configuration:**
```bash
RENDER_API_KEY=your_render_api_key_here
RENDER_SERVICE_ID=your_render_service_id_here
```

#### 2. CnameDnsChecker
Verifies CNAME DNS configuration using multiple DNS servers.

**Key Methods:**
- `verify_cname()` - Check single DNS server
- `verify_cname_multiple_dns()` - Check across Google DNS, Cloudflare, OpenDNS
- `dns_debug_info()` - Comprehensive DNS debugging information
- `domain_resolves?()` - Basic connectivity test

**DNS Target:**
- Production: `bizblasts.onrender.com`
- Development/Test: `localhost`

#### 3. CnameSetupService
Main orchestration service for the complete setup workflow.

**Key Methods:**
- `start_setup!()` - Initiate complete domain setup
- `restart_monitoring!()` - Restart DNS monitoring after timeout
- `force_activate!()` - Admin override to activate domain
- `status()` - Get current setup status

**Workflow:**
1. Validate business eligibility (Premium + custom_domain)
2. Add domain to Render.com
3. Update business status to `cname_pending`
4. Send setup instructions email
5. Start DNS monitoring (status → `cname_monitoring`)
6. Monitor DNS for up to 1 hour (12 checks × 5 minutes)
7. Activate on success or timeout with help

#### 4. DomainMonitoringService
Handles periodic DNS verification and state transitions.

**Key Methods:**
- `perform_check!()` - Single monitoring check with state updates
- `stop_monitoring!(reason)` - Stop monitoring process
- `monitoring_status()` - Get detailed monitoring information

**Verification Logic:**
- DNS CNAME must point to `bizblasts.onrender.com`
- Render.com must verify the domain
- Both conditions required for activation

#### 5. DomainRemovalService
Handles domain removal and tier downgrade scenarios.

**Key Methods:**
- `remove_domain!()` - Complete domain removal
- `handle_tier_downgrade!(new_tier)` - Remove domain on tier change
- `disable_domain!()` - Temporarily disable without removal
- `removal_preview()` - Preview impact of removal

### Background Jobs

#### DomainMonitoringJob
Runs DNS verification checks every 5 minutes.

**Features:**
- Automatic scheduling for eligible businesses
- Failure handling with retries
- Batch processing for multiple pending domains
- Graceful termination conditions

**Eligibility Criteria:**
- Status: `cname_monitoring`
- Monitoring active: `true`
- Attempts < 12
- Premium tier
- Custom domain host type

### Email Communications

#### DomainMailer
Handles all email communications for domain setup.

**Email Templates:**

1. **Setup Instructions (`setup_instructions.html.erb`)**
   - CNAME configuration details
   - Registrar-specific instructions
   - Monitoring timeline expectations

2. **Activation Success (`activation_success.html.erb`)**
   - Confirmation of domain activation
   - SSL certificate information
   - Update instructions for marketing materials

3. **Timeout Help (`timeout_help.html.erb`)**
   - Troubleshooting guidance
   - Common DNS issues
   - Support contact information

4. **Monitoring Restarted (`monitoring_restarted.html.erb`)**
   - Confirmation of monitoring restart
   - Status updates

### Admin Interface

#### ActiveAdmin Integration
Complete domain management interface in `app/admin/businesses.rb`.

**Features:**
- Domain status visualization
- Management action buttons
- Setup initiation
- Monitoring restart
- Force activation
- Domain removal
- Status filtering

**Admin Actions:**
- Start Domain Setup
- Restart Monitoring
- Force Activate Domain
- Disable Custom Domain

### Middleware Integration

#### ApplicationController Updates
Modified tenant resolution to only serve traffic for `cname_active` domains.

```ruby
def find_business_by_custom_domain
  Business.find_by(host_type: 'custom_domain', hostname: request.host, status: 'cname_active')
end
```

This ensures only verified domains can serve traffic.

## Business Model Methods

### CNAME Management Methods

```ruby
# Start monitoring workflow
business.start_cname_monitoring!

# Stop monitoring
business.stop_cname_monitoring!

# Check if due for next DNS check
business.cname_due_for_check?

# Increment check counter
business.increment_cname_check!

# Status transitions
business.cname_timeout!
business.cname_success!

# Eligibility check
business.can_setup_custom_domain?
```

### Automatic Tier Downgrade Handling

```ruby
# app/models/business.rb callback
after_update :handle_tier_downgrade, if: :saved_change_to_tier?

def handle_tier_downgrade
  # Automatically removes custom domain when downgrading from premium
end
```

## Monitoring & Verification Process

### DNS Monitoring Timeline

1. **Initial Setup** (Status: `cname_pending`)
   - Domain added to Render.com
   - Setup instructions emailed
   - Monitoring initiated

2. **Active Monitoring** (Status: `cname_monitoring`)
   - Check every 5 minutes
   - Maximum 12 attempts (1 hour total)
   - Dual verification: DNS + Render

3. **Success** (Status: `cname_active`)
   - Both DNS and Render verification passed
   - Success email sent
   - Domain ready to serve traffic

4. **Timeout** (Status: `cname_timeout`)
   - Maximum attempts reached
   - Help email sent
   - Manual intervention may be required

### Verification Criteria

**DNS Verification:**
- CNAME record exists
- Points to correct target (`bizblasts.onrender.com`)
- Verified by multiple DNS servers

**Render Verification:**
- Domain added to Render service
- Render.com API reports domain as verified
- SSL certificate provisioning initiated

## Error Handling & Recovery

### Automatic Recovery
- Network timeouts: Job retries with backoff
- Temporary DNS failures: Continue monitoring
- Render API errors: Logged but don't stop monitoring

### Manual Recovery
- Admin can restart monitoring
- Admin can force activate domains
- Detailed logging for troubleshooting

### User Recovery
- Clear email instructions
- Registrar-specific guidance
- Support contact information provided

## Security Considerations

### Access Control
- Only Premium tier businesses eligible
- Admin interface requires AdminUser authentication
- Tenant isolation maintained throughout

### Data Validation
- Domain name format validation
- DNS response verification
- API response sanitization

### Logging
- All domain operations logged
- Security events tracked
- No sensitive data in logs

## Performance Optimizations

### Database Indexes
- `cname_monitoring_active` for job queries
- `status` for filtering
- Compound indexes for monitoring queries

### Caching
- DNS results cached for 5 minutes
- Render API responses cached briefly
- Email delivery tracking

### Background Processing
- All long-running operations in background jobs
- Parallel processing for multiple domains
- Efficient job scheduling

## Testing

### Comprehensive Test Suite
- **RenderDomainService**: API integration mocking
- **CnameDnsChecker**: DNS resolution simulation
- **CnameSetupService**: Complete workflow testing
- **DomainMonitoringJob**: Background job testing
- **DomainRemovalService**: Cleanup testing
- **DomainMailer**: Email content verification
- **Business Model**: CNAME method testing

### Test Configuration
- Mock DNS responses
- Stub API calls
- Email delivery testing
- Background job testing

## Deployment Considerations

### Environment Variables
```bash
# Required for production
RENDER_API_KEY=your_render_api_key_here
RENDER_SERVICE_ID=your_render_service_id_here
SUPPORT_EMAIL=support@bizblasts.com
```

### Background Job Processing
- Ensure Solid Queue is running
- Monitor job queues
- Set up job failure alerts

### SSL Certificates
- Render.com handles SSL automatically
- Certificates may take up to 24 hours
- Monitor certificate status

## Monitoring & Observability

### Key Metrics
- Domain setup success rate
- Average setup time
- DNS verification failures
- Email delivery rates

### Logging
- Structured logging throughout
- Operation timing
- Error tracking
- User actions

### Alerts
- Job failures
- API errors
- High timeout rates
- SSL issues

## Future Enhancements

### Potential Improvements
- Webhook-based verification
- Multiple CNAME targets
- Subdomain wildcards
- Custom SSL certificates
- DNS record automation

### Scalability Considerations
- Rate limiting for APIs
- Batch processing optimization
- Distributed job processing
- Caching enhancements

This implementation provides a robust, user-friendly custom domain solution that integrates seamlessly with the existing BizBlasts architecture while maintaining security and performance standards.
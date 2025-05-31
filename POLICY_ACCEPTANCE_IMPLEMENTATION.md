# Policy Acceptance System Implementation

## Overview

This document describes the comprehensive policy acceptance system implemented for BizBlasts, which ensures legal compliance with GDPR/CCPA requirements and provides a robust framework for managing policy updates and user acceptance tracking.

## Features

### ✅ Signup Requirements
- **Business Users**: Must accept Terms of Service, Privacy Policy, Acceptable Use Policy, and Return Policy
- **Client Users**: Must accept Privacy Policy, Terms of Service, and Acceptable Use Policy
- **Termly Integration**: Maintains existing Termly embed integration for policy content
- **Per-User Tracking**: Individual policy acceptance tracking (not per business)

### ✅ Policy Update Management
- **Version Control**: Track different versions of each policy type
- **Activation System**: Activate new policy versions with automatic user notification
- **Change Tracking**: Record what changed in each policy version
- **Effective Dates**: Track when policy changes take effect

### ✅ Notification System
- **Email Notifications**: Automatic emails for Privacy Policy and Terms of Service changes
- **Dashboard Banners**: Visual notifications for all policy types
- **Blocking Modal**: Prevents site access until policies are accepted
- **Selective Notifications**: Different notification rules for different policy types

### ✅ Compliance Features
- **Audit Trail**: Complete tracking of who accepted what and when
- **IP Address Logging**: Record IP addresses for legal compliance
- **User Agent Tracking**: Track browser information for acceptance records
- **Forced Re-acceptance**: Block critical actions until updated policies are accepted

## Database Schema

### PolicyVersions Table
```ruby
create_table :policy_versions do |t|
  t.string :policy_type, null: false # 'terms_of_service', 'privacy_policy', 'acceptable_use_policy', 'return_policy'
  t.string :version, null: false # e.g., 'v1.0', 'v1.1'
  t.text :content # Optional: store policy content or reference
  t.string :termly_embed_id # Store Termly embed ID
  t.boolean :active, default: false
  t.boolean :requires_notification, default: false # For major changes requiring email notification
  t.datetime :effective_date
  t.text :change_summary # What changed in this version
  t.timestamps
end
```

### PolicyAcceptances Table
```ruby
create_table :policy_acceptances do |t|
  t.references :user, null: false, foreign_key: true
  t.string :policy_type, null: false
  t.string :policy_version, null: false
  t.datetime :accepted_at, null: false
  t.string :ip_address
  t.string :user_agent
  t.timestamps
end
```

### Users Table Additions
```ruby
add_column :users, :requires_policy_acceptance, :boolean, default: false
add_column :users, :last_policy_notification_at, :datetime
```

## Models

### PolicyVersion
- Manages different versions of policies
- Handles activation and deactivation of policy versions
- Triggers user notifications when activated
- Integrates with Termly embed IDs

### PolicyAcceptance
- Records individual user policy acceptances
- Tracks acceptance metadata (IP, user agent, timestamp)
- Provides query methods for checking acceptance status

### User (Enhanced)
- Added policy acceptance tracking methods
- Determines required policies based on user role
- Checks for missing policy acceptances

## Controllers

### PolicyAcceptancesController
- **GET /policy_status**: Returns user's policy acceptance status
- **POST /policy_acceptances**: Records individual policy acceptance
- **POST /policy_acceptances/bulk**: Records multiple policy acceptances

### PolicyEnforcement Concern
- Included in ApplicationController
- Checks policy acceptance requirements on each request
- Handles both AJAX and regular requests
- Skips check for policy-related actions

## Views and Frontend

### Policy Acceptance Modal
- **Location**: `app/views/shared/_policy_acceptance_modal.html.erb`
- **Features**:
  - Blocks all site access until policies are accepted
  - Shows required policies based on user role
  - Links to read each policy
  - Prevents modal dismissal without acceptance
  - Real-time button state updates

### JavaScript Module
- **Location**: `app/javascript/modules/policy_acceptance.js`
- **Features**:
  - Handles modal interactions
  - Manages checkbox states
  - Submits bulk policy acceptances
  - Shows success/error messages

### Registration Forms
- **Business Registration**: Includes all 4 policy checkboxes
- **Client Registration**: Includes 3 policy checkboxes (no return policy)
- **Validation**: Ensures all required policies are accepted before submission

## Email Notifications

### PolicyMailer
- Sends policy update notifications
- Includes change summaries and action links
- Styled HTML emails with clear call-to-action

### Notification Rules
- **Privacy Policy**: Email + Dashboard notification (all users)
- **Terms of Service**: Email + Dashboard notification (all users)
- **Acceptable Use Policy**: Dashboard notification only
- **Return Policy**: Email + Dashboard notification (business users only)

## Usage Examples

### Creating a New Policy Version
```ruby
# Create new privacy policy version
policy = PolicyVersion.create!(
  policy_type: 'privacy_policy',
  version: 'v2.0',
  termly_embed_id: 'new-embed-id',
  requires_notification: true,
  effective_date: Date.current,
  change_summary: 'Updated data retention policies and added new cookie tracking disclosures'
)

# Activate the new version (triggers notifications)
policy.activate!
```

### Checking User Policy Status
```ruby
user = User.find(123)

# Check if user needs to accept policies
user.needs_policy_acceptance? # => true/false

# Get missing policies
user.missing_required_policies # => ['privacy_policy', 'terms_of_service']

# Check specific policy acceptance
PolicyAcceptance.has_accepted_policy?(user, 'privacy_policy', 'v2.0') # => true/false
```

### Recording Policy Acceptance
```ruby
# Record acceptance (usually done via controller)
PolicyAcceptance.record_acceptance(user, 'privacy_policy', 'v2.0', request)

# Mark user as having accepted all current policies
user.mark_policies_accepted!
```

## Testing

### Model Tests
- **PolicyAcceptance**: Validation, scopes, acceptance recording
- **PolicyVersion**: Validation, activation, notification triggering
- **User**: Policy requirement checking, missing policy detection

### Controller Tests
- **PolicyAcceptancesController**: Status checking, acceptance recording
- **Registration Controllers**: Policy acceptance during signup

### System Tests
- **Modal Functionality**: Blocking behavior, acceptance flow
- **Integration**: End-to-end policy acceptance workflow

## Deployment Steps

1. **Run Migrations**:
   ```bash
   rails db:migrate
   ```

2. **Seed Initial Policy Versions**:
   ```bash
   rails db:seed
   ```

3. **Verify Termly Integration**:
   - Ensure Termly embed IDs are correct in seeds
   - Test policy page rendering

4. **Test Policy Flow**:
   - Create test users
   - Verify modal appears for new users
   - Test acceptance workflow

## Maintenance

### Adding New Policy Types
1. Add to `POLICY_TYPES` constant in both models
2. Update user role requirements in `User#required_policies_for_role`
3. Add policy path mapping in `PolicyVersion#policy_path`
4. Update registration forms if needed

### Updating Existing Policies
1. Create new PolicyVersion with incremented version
2. Set `requires_notification: true` for major changes
3. Activate the new version: `policy.activate!`
4. Monitor email delivery and user acceptance rates

### Monitoring and Analytics
- Track policy acceptance rates via PolicyAcceptance model
- Monitor email delivery success rates
- Check for users stuck in acceptance flow
- Review policy update effectiveness

## Security Considerations

- **IP Address Logging**: Stored for legal compliance and fraud detection
- **User Agent Tracking**: Helps identify automated vs. human acceptances
- **Timestamp Accuracy**: Critical for legal compliance
- **Data Retention**: Consider policy acceptance data retention requirements

## Compliance Notes

- **GDPR Article 7**: Requires clear consent records
- **CCPA Section 1798.135**: Requires opt-out mechanisms
- **Legal Validity**: IP address and timestamp provide legal evidence
- **Audit Trail**: Complete acceptance history maintained

## Future Enhancements

- [ ] Policy acceptance analytics dashboard
- [ ] Automated policy expiration reminders
- [ ] Multi-language policy support
- [ ] Advanced notification scheduling
- [ ] Policy acceptance reporting for legal teams 
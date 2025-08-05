
Examine /app, /spec, db/schema, read.me, custom.css, stripe files, routes and use list dir to understand the project. Open and read files. Create a plan to add calendar integrations that provide seamless two-way synchronization between the booking system and popular calendar applications.

Here are tips from claude. Use this info to help guide you when developing your plan some of their plan may already be completed (do not code anything yet, just plan).

# BizBlasts Calendar Integration - Development Implementation Prompt

## Project Overview

You are implementing a comprehensive calendar integration feature for BizBlasts, a Ruby on Rails 8.0.2 multi-tenant SaaS platform that serves businesses. The platform currently has a booking system and needs to integrate with external calendar providers (Google Calendar, Microsoft Outlook, and CalDAV) to provide two-way synchronization.

## Current Platform Architecture

### Technology Stack
- **Backend**: Ruby on Rails 8.0.2
- **Database**: PostgreSQL with multi-tenant architecture using `acts_as_tenant` gem
- **Background Jobs**: SolidQueue (database-backed)
- **Hosting**: Render ($7/month web service)
- **Authentication**: Devise
- **Authorization**: Pundit
- **Admin**: ActiveAdmin
- **Frontend**: Rails views with Hotwire (Turbo + Stimulus)
- **CSS**: Tailwind CSS via cssbundling-rails

### Existing Models (Key for Integration)
- `Business` - Multi-tenant root model
- `Booking` - Appointment/service bookings
- `StaffMember` - Business employees who provide services
- `Service` - Services offered by businesses
- `TenantCustomer` - Business customers
- `User` - Platform users (business owners, staff)

### Current Database Schema Relevant Fields
```ruby
# bookings table
t.datetime "start_time", null: false
t.datetime "end_time", null: false
t.bigint "service_id"
t.bigint "staff_member_id"
t.bigint "tenant_customer_id"
t.bigint "business_id"
t.integer "status", default: 0

# businesses table 
t.string "time_zone", default: "UTC"
t.string "name", null: false

# staff_members table
t.string "name", null: false
t.string "email"
t.jsonb "availability"
```

## Feature Requirements

### Primary Objectives
1. **One-way Sync**: Push BizBlasts bookings to external calendars
2. **Availability Import**: Read external calendar events to prevent double-booking
3. **Multi-Provider Support**: Google Calendar, Microsoft Outlook/Office 365, CalDAV
4. **Multi-Staff Support**: Different staff can connect different calendars
5. **Real-time Sync**: Changes reflect quickly across systems


### User Stories
1. **As a business owner**, I want to connect my Google Calendar so bookings appear automatically
2. **As a staff member**, I want my work calendar to prevent double-booking from my personal events
3. **As a business owner**, I want booking changes to sync immediately to all connected calendars
4. **As a business owner**, I want to see which calendars are connected and their sync status

## Implementation Requirements

### Phase 1: Core Infrastructure
- [ ] Database schema for calendar connections and sync tracking
- [ ] Google Calendar OAuth integration and API wrapper
- [ ] Basic booking sync (BizBlasts → Google Calendar)
- [ ] Calendar connection management UI
- [ ] Background job infrastructure for sync operations

### Phase 2: Microsoft Integration
- [ ] Microsoft Graph API OAuth integration
- [ ] Microsoft calendar sync with feature parity to Google
- [ ] Multi-provider connection management

### Phase 3: Availability Import
- [ ] External calendar event import
- [ ] Availability conflict detection in booking flow
- [ ] Background sync for availability updates

### Phase 4: CalDAV Support
- [ ] CalDAV protocol implementation
- [ ] Manual calendar configuration UI
- [ ] iCal format handling

## Technical Specifications

### Required Gems
Add these to Gemfile:
```ruby
gem 'google-apis-calendar_v3', '~> 0.31'
gem 'googleauth', '~> 1.8'
gem 'microsoft_graph', '~> 2.0'
gem 'oauth2', '~> 2.0'
gem 'icalendar', '~> 2.10'
gem 'calendav', '~> 0.3'
gem 'httparty', '~> 0.21'
```

### Database Schema Changes
You need to create these new tables:

1. **calendar_connections** - Store OAuth credentials and sync settings
2. **calendar_event_mappings** - Map BizBlasts bookings to external events
3. **calendar_sync_logs** - Track sync operations and errors
4. **external_calendar_events** - Cache external events for availability

Add these fields to existing tables:
- `bookings`: calendar sync status and tracking
- `staff_members`: calendar preferences
- `businesses`: calendar integration settings

### Service Architecture
Implement these core service classes:

1. **Calendar::BaseService** - Common functionality for all providers
2. **Calendar::GoogleService** - Google Calendar API integration
3. **Calendar::MicrosoftService** - Microsoft Graph API integration 
4. **Calendar::CaldavService** - CalDAV protocol implementation
5. **Calendar::SyncCoordinator** - Orchestrates sync operations
6. **Calendar::OauthHandler** - Manages OAuth flows

### Background Jobs
Create these background jobs:

1. **Calendar::SyncBookingJob** - Sync individual booking to external calendars
2. **Calendar::DeleteBookingJob** - Remove booking from external calendars
3. **Calendar::ImportAvailabilityJob** - Import external events for availability
4. **Calendar::BatchSyncJob** - Batch sync operations

### API Integrations

#### Google Calendar API
- **OAuth Scopes**: `https://www.googleapis.com/auth/calendar`
- **Key Operations**:
 - Create/update/delete events
 - List calendars
 - Watch for changes (webhooks)
- **Rate Limits**: 1,000 requests/100 seconds/user

#### Microsoft Graph API 
- **OAuth Scopes**: `https://graph.microsoft.com/Calendars.ReadWrite`
- **Key Operations**:
 - Create/update/delete events via `/me/events`
 - List calendars
 - Subscribe to change notifications
- **Rate Limits**: Variable by tenant

#### CalDAV Protocol
- **Authentication**: Basic auth or app-specific passwords
- **Operations**: HTTP methods (GET, PUT, DELETE) on .ics files
- **Providers**: iCloud, Nextcloud, various servers

## Implementation Steps

### Step 1: Setup and Configuration
1. Add required gems to Gemfile and bundle install
2. Set up Google and Microsoft API credentials in Rails credentials
3. Configure OAuth redirect URLs in provider consoles
4. Add calendar configuration to Rails application config

### Step 2: Database Schema
1. Generate and run database migrations for new tables
2. Add calendar-related fields to existing models
3. Update model associations and validations
4. Add appropriate database indexes

### Step 3: Core Service Implementation
1. Implement Calendar::BaseService with common patterns
2. Create Google Calendar OAuth flow and API wrapper
3. Implement booking sync to Google Calendar
4. Add basic error handling and retry logic

### Step 4: User Interface
1. Calendar integrations management page
2. Implement OAuth connection flow UI
3. Add sync status indicators to booking views
4. Ensure connection settings and management interface

### Step 5: Microsoft Integration
1. Implement Microsoft Graph OAuth flow
2. Create Microsoft calendar service with API wrapper
3. Ensure feature parity with Google integration
4. Add Microsoft provider to UI

### Step 6: Background Processing
1. Implement background jobs for sync operations
2. Add job scheduling for regular availability imports
3. Implement retry logic and error handling
4. Add job monitoring and status tracking

### Step 7: Availability Integration
1. Import external calendar events
2. Integrate availability checking into booking flow
3. Add conflict detection and prevention
4. Update AvailabilityService to consider external events

### Step 8: CalDAV Implementation
1. Implement CalDAV protocol support
2. Add manual calendar configuration UI
3. Handle various CalDAV server implementations
4. Add iCal parsing and generation

## Security Requirements

### Data Protection
- Encrypt all OAuth tokens using Rails message verifiers
- Use HTTPS for all external API communications
- Implement proper CSRF protection for OAuth flows
- Store minimal necessary data from external calendars

### Authentication & Authorization
- Validate OAuth state parameters to prevent CSRF
- Implement proper scope validation for API access
- Use business-level authorization for calendar management
- Ensure staff can only access their own calendar connections

### Error Handling
- Never expose sensitive tokens in error messages
- Implement proper rate limiting and backoff
- Log security-relevant events appropriately
- Handle OAuth token expiration gracefully

## Testing Requirements

### Unit Tests
- [ ] OAuth flow handling and token management
- [ ] Calendar service API interactions (mocked)
- [ ] Event mapping and transformation logic
- [ ] Availability conflict detection algorithms

### Integration Tests 
- [ ] Complete OAuth authorization flows
- [ ] Booking creation with calendar sync
- [ ] Booking updates and deletions with sync
- [ ] Availability import and conflict detection
- [ ] Background job processing

### Testing Checklist
- [ ] Connect Google Calendar successfully
- [ ] Connect Microsoft Calendar successfully 
- [ ] Create booking and verify sync to external calendar
- [ ] Update booking and verify changes sync
- [ ] Delete booking and verify removal from external calendar
- [ ] Test availability import and conflict prevention
- [ ] Verify error handling and user feedback
- [ ] Test with multiple staff members and calendars

## Success Criteria

### Functional Requirements
- [ ] Users can connect Google and Microsoft calendars via OAuth
- [ ] Bookings automatically appear in connected external calendars
- [ ] Booking changes sync to external calendars within 5 minutes
- [ ] External calendar events prevent double-booking in BizBlasts
- [ ] Multiple staff members can connect different calendars
- [ ] Clear sync status and error reporting for users

### Performance Requirements
- [ ] OAuth connection completes within 30 seconds
- [ ] Individual booking sync completes within 60 seconds
- [ ] Availability import processes 100 events within 30 seconds
- [ ] UI remains responsive during background sync operations

### Quality Requirements
- [ ] 95%+ sync success rate under normal conditions
- [ ] Graceful handling of API outages and rate limits
- [ ] No data loss during sync operations
- [ ] Clear error messages for user troubleshooting

## Multi-Tenant Considerations

### Data Isolation
- All calendar connections must be properly scoped to business tenant
- Use `acts_as_tenant` consistently throughout calendar models
- Ensure background jobs maintain proper tenant context
- Prevent cross-tenant data access in all calendar operations

### Scaling Considerations 
- Design for multiple businesses per Rails instance
- Implement efficient batch processing for sync operations
- Use database-backed background jobs (SolidQueue)
- Consider API rate limits across all tenants

### Business Use Cases
- **Landscaping Companies**: Sync service calls with crew calendars
- **Pool Service**: Coordinate maintenance schedules across routes
- **HVAC Contractors**: Prevent conflicts with emergency calls
- **Home Services**: Coordinate multi-person service appointments

### Seasonal Considerations
- Consider time zone handling

## Documentation Requirements

### User Documentation
- [ ] Calendar connection setup guides for each provider
- [ ] Troubleshooting guide for common sync issues
- [ ] Best practices for calendar organization
- [ ] Privacy and data usage explanation

### Developer Documentation
- [ ] API integration patterns and error handling
- [ ] Background job processing architecture
- [ ] Database schema and model relationships
- [ ] Adding support for new calendar providers

## Deployment and Monitoring

### Production Deployment
- Use Rails credentials for API keys (never environment variables)
- Configure webhook URLs for production domain
- Set up monitoring for background job failures
- Implement health checks for external API connectivity

### Monitoring Requirements
- Track sync success/failure rates by provider
- Monitor API response times and rate limit usage
- Alert on high error rates or service degradation
- Track user adoption and feature usage metrics

## Example Code Structure

Your implementation should follow this general structure and some of the infrastructure may already exist:

```
app/
├── controllers/
│   ├── calendar_integrations_controller.rb
│   └── api/calendar_webhooks_controller.rb
├── jobs/
│   └── calendar/
│       ├── sync_booking_job.rb
│       ├── import_availability_job.rb
│       └── batch_sync_job.rb
├── models/
│   ├── calendar_connection.rb
│   ├── calendar_event_mapping.rb
│   └── calendar_sync_log.rb
├── services/
│   └── calendar/
│       ├── base_service.rb
│       ├── google_service.rb
│       ├── microsoft_service.rb
│       └── sync_coordinator.rb
└── views/
   └── calendar_integrations/
       ├── index.html.erb
       ├── show.html.erb
       └── new.html.erb
```

## Important Notes for Implementation

1. **Start Simple**: Begin with Google Calendar one-way sync, then expand
2. **Error Handling**: Robust error handling is critical for external API integrations
3. **Rate Limits**: Respect API rate limits and implement proper backoff strategies
4. **User Experience**: Provide clear feedback on sync status and any issues
5. **Testing**: Test thoroughly with real calendar providers, not just mocks
6. **Security**: Never log or expose OAuth tokens or sensitive calendar data

This calendar integration will significantly enhance BizBlasts' value proposition for businesses by eliminating manual calendar management and preventing scheduling conflicts.

Here is the analysis from o3:

Here’s what I found in the codebase and a concrete, incremental plan to reach full two-way calendar sync.

1. What already exists  
   • `app/services/calendar_sync_service.rb` – a stub with create / update / delete / import methods and a tiny RSpec.  
   • `Integration` model (`kind` enum includes `google_calendar`) and `IntegrationCredential` model (generic, no calendar providers yet).  
   • No OAuth flows, background jobs, routes, UI, or database columns such as `calendar_event_id` on `bookings`.  
   • No calendar-specific tables (`calendar_connections`, `calendar_event_mappings`, etc.).  
   • No routes or controllers related to calendars.  
   → In short, only a placeholder service and a high-level “integration” model exist. Everything else from the Claude spec is still to be built.

2. High-level direction  
   • Keep the existing stub as the façade (`CalendarSyncService`) but refactor it to delegate to new provider-specific service classes.  
   • Introduce new, focused tables rather than over-loading the generic `integrations` table, because staff-level OAuth tokens and per-booking event IDs don’t map cleanly to the current structure.  
   • Re-use the tenant isolation helpers (`acts_as_tenant`) and SolidQueue for background work.

3. Proposed database schema (migrations)  
   a. `calendar_connections`  
      - id, business_id, staff_member_id, provider (enum: google, microsoft, caldav), uid (external calendar id, if needed)  
      - access_token (encrypted), refresh_token (encrypted), token_expires_at, scopes, sync_token (for delta queries), connected_at, last_synced_at, active:boolean  
   b. `calendar_event_mappings`  
      - id, booking_id, calendar_connection_id, external_event_id, external_calendar_id, status (synced/pending/failed), last_synced_at, last_error  
   c. `calendar_sync_logs` (optional but useful)  
      - id, calendar_event_mapping_id, action (create/update/delete/import), outcome, message, metadata (jsonb)  
   d. `external_calendar_events`  
      - id, calendar_connection_id, external_event_id, external_calendar_id, starts_at, ends_at, summary, last_imported_at

   Add columns:  
   • `bookings.calendar_event_status` (enum) and maybe `calendar_event_id` (string) if you prefer quick look-ups without a join.  
   • `staff_members.default_calendar_connection_id` (optional) for easy routing of new bookings.

4. Gemfile additions  
   – exactly the list from the Claude prompt (`google-apis-calendar_v3`, `googleauth`, `microsoft_graph`, `oauth2`, `icalendar`, `calendav`, `httparty`).  
   – ensure `attr_encrypted` or Rails’ own encryption (`has_encrypted :access_token`) is available for tokens.

5. Service / job architecture  
   ```
   app/
   ├── services/calendar/
   │   ├── base_service.rb               # shared helpers (refresh_token!, handle_rate_limits, etc.)
   │   ├── google_service.rb
   │   ├── microsoft_service.rb
   │   ├── caldav_service.rb
   │   ├── sync_coordinator.rb           # called by jobs, decides which events/bookings need sync
   │   └── oauth_handler.rb              # generates auth URLs, handles callbacks
   └── jobs/calendar/
       ├── sync_booking_job.rb
       ├── delete_booking_job.rb
       ├── import_availability_job.rb
       └── batch_sync_job.rb
   ```

   `CalendarSyncService` becomes a thin façade that enqueues these jobs or calls `SyncCoordinator`.

6. Controllers & routes  
   ```
   GET  /manage/settings/calendars               → BusinessManager::CalendarIntegrationsController#index
   POST /manage/settings/calendars/:provider     → …#create   (kick off OAuth)
   GET  /oauth/calendar/:provider/callback       → CalendarOauthController#callback (outside tenant scope)
   POST /api/calendar/webhooks/google            → Api::CalendarWebhooksController#google   (future)
   ```
   Use existing `SubdomainConstraint` for tenant routes; OAuth callback stays on main domain (safer).

7. UI  
   • Business-manager settings page section “Calendar Integrations” listing staff members & connected calendars.  
   • Switch/toggle per staff member to mark the default calendar for push-sync.  
   • Sync status badges + manual “Resync” button that enqueues `BatchSyncJob`.

8. Background job flow (Google example)  
   a. Booking created → `after_commit` hook enqueues `Calendar::SyncBookingJob`.  
   b. Job loads connection, calls `Calendar::GoogleService.create_event` → writes mapping.  
   c. If booking updated/cancelled, similar jobs run.  
   d. `ImportAvailabilityJob` runs every N minutes (SolidQueue schedule) per connection, fetches events with `sync_token`, stores/updates `external_calendar_events`.  
   e. `AvailabilityService` (already exists) is extended to also query `external_calendar_events` when calculating conflicts.

9. Security / encryption  
   • Store tokens with Rails’ built-in encryptor (`encrypts :access_token`) in the model.  
   • Use Rails credentials for client IDs/secrets; never expose in logs.  
   • Validate OAuth state param with a short-lived, tenant-scoped nonce record or signed cookie.

10. Tests (RSpec + Jest)  
   Unit:  
   • `Calendar::GoogleService` – mocked HTTP interactions via `WebMock`.  
   • `Calendar::OauthHandler` – state/nonce validation.  
   • `AvailabilityService` conflict logic including external events.  
   Integration/system:  
   • Full OAuth flow using Google’s sandbox (or stubbed responses).  
   • Booking lifecycle → calendar event created/updated/deleted.  
   • Multiple staff members & multiple providers.

11. Incremental delivery roadmap  
   Phase 1 (Google one-way):  
   • Gems + migrations  
   • OAuth flow & connection UI  
   • `google_service.rb` create/update/delete  
   • `SyncBookingJob` (create only)  
   • Minimal tests  
   Phase 2 (two-way + Microsoft):  
   • Availability import & conflict checking  
   • Microsoft Graph support  
   • Update/delete jobs  
   • Webhook/watch support for near-real-time updates  
   Phase 3 (CalDAV + polishing):  
   • CalDAV service with manual URL/password entry  
   • Batch sync & retry strategies  
   • Admin monitoring dashboard, metrics, alerting

12. Open questions / decisions needed  
   1. Do you want **per-staff** or **per-business** calendar connections (or both)?  
-Should be both, technically connected by email so it shouldn’t matter
   2. Should we keep `calendar_event_id` directly on `bookings` (fast, simple) in addition to `calendar_event_mappings`, or rely solely on the join table?  
		-Yes, keep it fast and simple 


Whenever you have a question try to research and answer it yourself. If you absolutely cannot answer yourself do not make any assumptions you may ask me for clarification. Please think deeply and review this entire plan, do you have any questions?
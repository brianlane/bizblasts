# Calendar Integration Setup

This document provides instructions for setting up calendar integrations with Google Calendar and Microsoft Outlook.

## Overview

The calendar integration system provides:
- **Two-way sync** between BizBlasts bookings and external calendars
- **Conflict prevention** by importing external calendar events
- **Multi-provider support** for Google Calendar and Microsoft Outlook
- **Staff-level connections** allowing different team members to connect different calendars
- **Automatic sync** when bookings are created, updated, or cancelled

## Architecture

### Core Components

1. **Models**
   - `CalendarConnection` - Stores OAuth credentials and connection metadata
   - `CalendarEventMapping` - Maps BizBlasts bookings to external calendar events
   - `CalendarSyncLog` - Audit trail for sync operations
   - `ExternalCalendarEvent` - Cached external events for availability checking

2. **Services**
   - `Calendar::SyncCoordinator` - Orchestrates sync operations
   - `Calendar::GoogleService` - Google Calendar API integration
   - `Calendar::MicrosoftService` - Microsoft Graph API integration
   - `Calendar::OauthHandler` - Secure OAuth flow management

3. **Background Jobs**
   - `Calendar::SyncBookingJob` - Sync individual bookings
   - `Calendar::DeleteBookingJob` - Remove bookings from calendars
   - `Calendar::ImportAvailabilityJob` - Import external events
   - `Calendar::BatchSyncJob` - Bulk operations

## Setup Instructions

### 1. Google Calendar Setup

1. **Create Google Cloud Project**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select existing one
   - Enable the Google Calendar API

2. **Create OAuth Credentials**
   - Go to APIs & Services > Credentials
   - Click "Create Credentials" > "OAuth 2.0 Client ID"
   - Set application type to "Web application"
   - Add authorized redirect URIs:
     - `https://yourdomain.com/oauth/calendar/google/callback`
     - For development: `http://localhost:3000/oauth/calendar/google/callback`

3. **Add Credentials to Rails**
   ```bash
   EDITOR="code --wait" rails credentials:edit
   ```
   
   Add to credentials file:
   ```yaml
   google_calendar:
     client_id: your_google_client_id
     client_secret: your_google_client_secret
   ```

### 2. Microsoft Graph Setup

1. **Register Azure Application**
   - Go to [Azure Portal](https://portal.azure.com/)
   - Navigate to Azure Active Directory > App registrations
   - Click "New registration"
   - Set redirect URI: `https://yourdomain.com/oauth/calendar/microsoft/callback`

2. **Configure API Permissions**
   - In your app registration, go to "API permissions"
   - Add Microsoft Graph permissions:
     - `Calendars.ReadWrite` (Delegated)
     - `offline_access` (Delegated)
   - Grant admin consent if required

3. **Get Client Secret**
   - Go to "Certificates & secrets"
   - Create a new client secret
   - Copy the value (you won't see it again)

4. **Add Credentials to Rails**
   ```bash
   EDITOR="code --wait" rails credentials:edit
   ```
   
   Add to credentials file:
   ```yaml
   microsoft_graph:
     client_id: your_azure_application_id
     client_secret: your_azure_client_secret
   ```

### 3. Production Deployment

1. **Environment Variables** (if not using Rails credentials)
   ```bash
   GOOGLE_CALENDAR_CLIENT_ID=your_google_client_id
   GOOGLE_CALENDAR_CLIENT_SECRET=your_google_client_secret
   MICROSOFT_GRAPH_CLIENT_ID=your_azure_application_id
   MICROSOFT_GRAPH_CLIENT_SECRET=your_azure_client_secret
   ```

2. **Background Job Processing**
   Ensure SolidQueue is running:
   ```bash
   bundle exec rails solid_queue:start
   ```

3. **Regular Availability Import**
   Set up a cron job to import availability regularly:
   ```ruby
   # In a scheduled job or cron
   Calendar::ImportAvailabilityJob.schedule_for_all_staff
   ```

## Usage

### Connecting Calendars

1. **Business Manager Access**
   - Navigate to Settings > Calendar Integrations
   - Select a staff member
   - Click "Connect Google Calendar" or "Connect Microsoft Calendar"
   - Complete OAuth authorization

2. **Setting Default Calendar**
   - Each staff member can have multiple calendar connections
   - Set one as "default" for new booking sync
   - Existing bookings continue syncing to their original calendars

### Automatic Sync

Bookings are automatically synced when:
- New booking is created
- Booking details are updated (time, service, customer, etc.)
- Booking is cancelled or completed
- Staff member is changed

### Manual Operations

1. **Resync Individual Connection**
   - Go to Calendar Integrations
   - Click "Resync" next to a connection
   - Triggers immediate sync of pending bookings and availability import

2. **Batch Operations**
   - "Sync All Pending Bookings" - Sync any failed or new bookings
   - "Import All Availability" - Refresh external calendar events

### Troubleshooting

1. **Check Sync Status**
   - Calendar Integrations page shows sync status for each staff member
   - Connection details page shows recent sync logs
   - Failed syncs are automatically retried up to 3 times

2. **Common Issues**
   - **Token Expired**: Staff member needs to reconnect calendar
   - **Permission Denied**: Check OAuth scopes and admin consent
   - **Rate Limited**: Automatic retry with exponential backoff
   - **API Errors**: Check service status pages for Google/Microsoft

3. **Debug Tools**
   ```ruby
   # In Rails console
   
   # Check connection status
   staff = StaffMember.find_by(email: 'staff@example.com')
   staff.calendar_connections.each do |conn|
     puts "#{conn.provider}: #{conn.active? ? 'Active' : 'Inactive'}"
     puts "Last sync: #{conn.last_sync_status}"
   end
   
   # Manual sync test
   booking = Booking.last
   coordinator = Calendar::SyncCoordinator.new
   result = coordinator.sync_booking(booking)
   puts result ? "Success" : coordinator.errors.full_messages
   
   # Check external events
   ExternalCalendarEvent.where(calendar_connection: staff.calendar_connections)
                       .where('starts_at > ?', Time.current)
                       .order(:starts_at)
   ```

## Security Considerations

1. **OAuth Tokens**
   - Access tokens are encrypted at rest
   - Refresh tokens allow automatic token renewal
   - Tokens are never logged or exposed in error messages

2. **State Validation**
   - OAuth state parameter prevents CSRF attacks
   - State includes business and staff member verification
   - Short expiration time (15 minutes)

3. **API Rate Limits**
   - Automatic retry with exponential backoff
   - Distributed requests to avoid hitting limits
   - Per-connection rate limiting

4. **Data Isolation**
   - All operations are properly tenant-scoped
   - Staff members can only access their own connections
   - Business managers can view all connections for their business

## Monitoring

1. **Sync Statistics**
   - Available in Calendar Integrations UI
   - Shows success rates and recent failures
   - 24-hour rolling statistics

2. **Background Job Monitoring**
   - Use SolidQueue web UI for job status
   - Failed jobs are automatically retried
   - Monitor queue length and processing times

3. **Logging**
   - All sync operations are logged
   - Error details available in CalendarSyncLog model
   - Rails logs include provider-specific error handling

## API Limits

### Google Calendar API
- **Rate Limit**: 1,000 requests per 100 seconds per user
- **Daily Quota**: 1,000,000 requests per day
- **Batch Operations**: Not implemented (future enhancement)

### Microsoft Graph API
- **Rate Limit**: Variable by tenant (typically 10,000+ requests per 10 minutes)
- **Throttling**: Automatic retry with Retry-After header
- **Resource-specific limits**: Different for calendars vs. other resources

## Future Enhancements

1. **CalDAV Support**: For iCloud, Nextcloud, and other CalDAV servers
2. **Webhook Support**: Real-time sync using calendar webhooks
3. **Batch Operations**: More efficient API usage for large datasets
4. **Advanced Scheduling**: Smart conflict resolution and suggestion engine
5. **Analytics Dashboard**: Detailed sync metrics and usage statistics
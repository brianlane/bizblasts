# BizBlasts - Technical Architecture (Rails)

## Architecture Overview

BizBlasts will implement a Ruby on Rails monolithic application with multi-tenant architecture, hosted on Render's platform. This approach provides a cohesive framework for both the admin dashboard and client websites while maintaining efficient resource utilization and cost control.

## Technology Stack

### Backend
- **Framework**: Ruby on Rails 8.0.2
- **API**: RESTful Rails controllers with some JSON endpoints
- **Database**: PostgreSQL on Render (1GB free tier)
- **ORM**: Active Record
- **Background Jobs**: Sidekiq (for scheduled tasks)
- **Caching**: Rails cache with Redis (free tier on Render)
- **File Storage**: Render disk storage or ActiveStorage with AWS S3 if needed
- **Hosting**: Render Web Service ($7/month)

### Frontend
- **View Layer**: Rails View templates
- **CSS**: CSS managed via `cssbundling-rails`
- **JavaScript**: js for interactive elements
- **Responsive Design**: Mobile-first approach with CSS
- **Asset Pipeline**: Propshaft for efficient asset handling

### Authentication & Authorization
- **User Authentication**: Devise (including `devise-jwt` for potential API auth)
- **Authorization**: Pundit
- **Multi-tenancy**: acts_as_tenant gem (schema-based)
- **Admin Controls**: ActiveAdmin for management dashboard

### Integrations (Planned/Current)
- **Payments**: Stripe Connect (Placeholder implementation via `StripeService`, needs build-out for Products/Orders/Invoices)
- **Email**: ActionMailer with Render SMTP or SendGrid
- **SMS Notifications**: Twilio (Planned - Not Yet Implemented)
- **DNS**: Render managed DNS
- **Analytics**: Google Analytics with Turbo compatibility
- **SEO**: Meta tags with proper Rails helpers
- **Social Media**: Integration with popular platforms
- **Calendar**: Google Calendar and iCal integration

### DevOps
- **CI/CD**: GitHub Actions integrated with Render
- **Version Control**: GitHub
- **Testing**: RSpec, Capybara, and FactoryBot
- **Monitoring**: Render built-in monitoring
- **Error Tracking**: Honeybadger free tier

## Multi-Tenant Architecture

### Schema-Based Multi-Tenancy

BizBlasts will utilize the acts_as_tenant gem for schema-based multi-tenancy:

#### Tenant Isolation
- Each client business gets its own PostgreSQL schema
- Complete data isolation between tenants
- Shared application code across all tenants
- Public schema for shared/global data

#### Subdomain Routing
- Each client site uses a subdomain (business.bizblasts.com)
- Paid tiers use custom domains (Future Feature)
- Subdomain recognition and tenant switching via middleware (`app/middleware/tenant_middleware.rb`)
- Fallback to marketing site for unknown subdomains


#### Tenant Context Management
- Automatic tenant switching based on subdomain/domain
- Background jobs maintain tenant context (via SolidQueue adapters)
- API endpoints include tenant context in requests (if applicable)
- Development tools for testing across tenants



    *   Using extensions or custom decorators.

### Admin Dashboard

A single admin interface manages all client websites:

#### Admin Interface Architecture
- ActiveAdmin-based dashboard for site management
- Tenant switching capability for admin users
- Global reporting across all tenants
- Centralized management of templates and shared assets
- Client analytics and business metrics
- Comprehensive reporting tools

#### Template System
- Database-driven templates stored in public schema
- Theme customization via application settings
- Component-based layout system
- Shared partials across client sites

#### Notifications
- Basic email/SMS reminders via `BookingMailer`, `ReminderMailer`, `SmsService`, and corresponding jobs (`BookingReminderJob`, `SmsNotificationJob`). Requires Twilio setup.

### Staff Management
- **Models**: `Invoice`.
- **Controllers**: `InvoicesController`.
- **Jobs**: `InvoiceReminderJob`.
- **Mailers**: `InvoiceMailer`.
*Note: `Invoice` model will be extended to support `LineItem`s for both services and products.*

### CMS (Basic)
- **Models**: `Page`, `PageSection`, `TemplatePageSection`.
- **Admin**: Configurable via ActiveAdmin.

### Product Management (Custom)
- **Models**: `Product`, `Order`, `LineItem` (potentially `ProductVariant`). All tenant-scoped.
- **Controllers**: `ProductsController`, `OrdersController`, `CartController` (handling both standalone orders and booking add-ons).
- **Logic**: Custom logic for cart management, order creation, adding products to invoices.
- **Admin**: Integration into ActiveAdmin for `Product` and `Order` management.

## Enhanced Booking System

### Advanced Scheduling Architecture

Based on simplybook.me analysis, implementing a more robust booking system:

#### Multi-Staff Scheduling
- Staff profiles and availability management
- Service assignment to specific staff members
- Staff-specific booking rules
- Staff performance metrics

#### Appointment Types
- Custom appointment type definitions, including support for 'Standard' and 'Experience' service types with configurable minimum and maximum bookings, and managing available spots for 'Experience' services.
- Duration and buffer time settings
- Capacity settings (group bookings)
- Resource requirements tracking

#### Customer-Facing Features
- Client accounts and login
- Booking history and management
- Favorite providers selection
- Rebooking from history
- Ability to specify booking quantity for 'Experience' services.

#### Notification System
- SMS appointment reminders
- Email confirmations and updates
- Customizable notification templates
- Staff notifications for new bookings

## Component-Based Design

### Rails Component Organization

The application will utilize a component-based approach with Rails:

#### View Components
- Organized by business domain
- Reusable across different tenant websites
- Template inheritance for common layouts
- Controllers for interactive elements

#### Shared Components
- Header/footer/navigation components
- Booking/scheduling components
- Potential future components: Payment form, Gallery, Contact form, Client review display.
- Product display components (grid, detail).
- Cart/Order summary components.

#### Phoenix-Specific Components
- Service area map components for Phoenix
- Local SEO components with Phoenix metadata
- Seasonal content blocks for desert climate
- Phoenix neighborhood selectors

## Database Architecture

### PostgreSQL Schema Design

Efficient database design to handle multi-tenant data:

#### Core Schemas
- **public**: Global application data, templates, admin users
- **tenant_xxx**: Client-specific schemas (one per business)

#### Public Schema Tables
```
templates
├── id
├── name
├── industry
├── description
├── default_pages (jsonb)
├── created_at
├── updated_at

admin_users
├── id
├── email
├── encrypted_password
├── role
├── created_at
├── updated_at

businesses
├── id
├── schema_name
├── name
├── subdomain
├── custom_domain
├── plan_id
├── status
├── created_at
├── updated_at

client_businesses -- Purpose needs review/clarification
```

#### Tenant Schema Tables (Key Examples - Per Client)
```
-- Note: business_details table from PRD seems covered by `businesses` in public schema.
--       Customization might occur via tenant-specific settings table later.

services
├── id
├── name
├── description
├── price
├── duration
├── featured
├── type (enum: 'standard', 'experience')
├── min_bookings (integer)
├── max_bookings (integer)
├── spots (integer)

staff_members
├── id
├── name
├── title
├── bio
├── photo
├── services (jsonb)
├── availability (jsonb)

pages
├── id
├── title
├── slug
├── content
├── meta_description

bookings
├── id
├── service_id
├── staff_member_id
├── customer_name
├── customer_email
├── customer_phone
├── start_time
├── end_time
├── status
├── notes
├── quantity (integer)

customers
├── id
├── name
├── email
├── phone
├── address
├── notes
├── custom_fields (jsonb)

invoices
├── id
├── customer_id
├── amount
├── status
├── due_date
├── promotion_id
├── discount_amount
├── created_at
├── updated_at

marketing_promotions
├── id
├── name
├── description
├── discount_amount
├── discount_type
├── valid_from
├── valid_until
├── code
├── usage_limit

products
├── id
├── business_id
├── name
├── description
├── price
├── sku (optional)
├── stock_quantity (basic inventory)
├── active
├── featured

├── created_at
├── updated_at

product_variants (Optional - if supporting variants)
├── id
├── product_id
├── name (e.g., "Large", "Red")
├── sku
├── price_modifier
├── stock_quantity
├── created_at
├── updated_at

orders (For standalone product purchases)
├── id
├── business_id
├── tenant_customer_id
├── order_number
├── status (e.g., pending, processing, shipped, completed, cancelled)
├── total_amount
├── tax_amount (manual)
├── shipping_amount (manual)
├── shipping_address (jsonb or separate fields)
├── shipping_method (manual)
├── notes
├── created_at
├── updated_at

line_items (Links Products/Variants to Orders and Invoices)
├── id
├── lineable_type (e.g., 'Order', 'Invoice')
├── lineable_id
├── product_id
├── product_variant_id (optional)
├── quantity
├── price (at time of purchase)
├── total_amount
├── created_at
├── updated_at
```

### Database Optimization
- Proper indexing for tenant context queries
- Connection pooling configuration
- Regular vacuum and maintenance
- Query optimization for common patterns
- Caching strategy for frequent queries

## Deployment Architecture

### Render Deployment Setup

Streamlined deployment process with Render's platform:

#### Web Service Configuration
- Ruby on Rails web service ($7/month)
- Automatic SSL certificate management
- Zero-downtime deployments
- Build time optimizations
- Custom domain configuration

#### Database Configuration
- Render PostgreSQL (free tier - 1GB)
- Automated backups
- Connection pooling
- Monitoring and metrics
- Schema-based multi-tenancy support

#### Deployment Pipeline
1. Push to GitHub repository main branch
2. GitHub Actions runs tests
3. On successful tests, Render builds new image
4. Render deploys to production
5. Zero-downtime cutover to new version
6. Automatic database migrations

## Security Architecture

### Rails Security Best Practices

Comprehensive security approach leveraging Rails built-in features:

#### Authentication Security
- Devise with secure password handling
- CSRF protection
- Session management and security
- Two-factor authentication for admin users
- Password policies and expiration

#### Authorization Controls
- Pundit policies for fine-grained authorization
- Tenant context validation
- Resource-based permissions
- Admin role hierarchy
- Audit logging of sensitive actions

#### Data Protection
- Database encryption for sensitive fields
- Proper parameter sanitization
- SQL injection prevention
- XSS protection
- HTTPS enforcement

## Marketing Features Architecture

### Promotional System Design

Based on simplybook.me analysis, implementing marketing features:

#### Coupon and Discount System
- Promotional code generation
- Discount calculation engine
- Usage tracking and limitations
- Expiration management
- Analytics on promotion effectiveness

#### Client Rewards Program
- Customer loyalty tracking
- Points or visit-based rewards
- Automated reward notifications
- Referral tracking and incentives
- Client retention analytics

#### Email Marketing Integration
- Campaign management system
- Template-based email creation
- Client segmentation
- Sending schedule management
- Open and click tracking

## SEO and Performance Optimization

### Rails-Based SEO Strategy

Leveraging Rails' capabilities for search engine optimization:

#### On-Page SEO
- Dynamically generated meta tags
- Structured data (JSON-LD)
- Semantic HTML with Rails helpers
- Proper heading hierarchy
- XML sitemap generation
- Local business schema implementation
- Review aggregation markup

#### Performance Optimization
- Asset minification and bundling
- Proper HTTP caching headers
- Database query optimization
- Lazy loading of images
- Critical CSS path optimization

#### Mobile Optimization
- Responsive design through CSS
- Mobile-first approach
- Touch-friendly interface elements
- Performance testing on mobile devices
- Google mobile-friendly testing

## Advanced Form System

### Dynamic Intake Form Architecture

Framework for sophisticated customer intake forms:

#### Form Builder System
- Dynamic field generation
- Conditional logic implementation
- Form versioning and history
- Field validation rules
- Custom field types

#### Form Data Structure
```
form_templates
├── id
├── business_id
├── name
├── description
├── status
├── created_at
├── updated_at

form_fields
├── id
├── form_template_id
├── label
├── field_type
├── required
├── options (jsonb)
├── validation_rules (jsonb)
├── conditional_display (jsonb)
├── order
├── placeholder
├── help_text

form_submissions
├── id
├── form_template_id
├── customer_id
├── booking_id
├── submission_data (jsonb)
├── created_at
├── updated_at
```

#### Conditional Logic Implementation
- Show/hide fields based on previous answers
- Required field toggling
- Calculated fields
- Branching question sequences
- Skip logic

#### Form Rendering Engine
- Client-side form building
- Validation implementation
- Conditional rendering
- Mobile-optimized display
- Accessibility compliance

## Document Management System

### Customer Document Architecture

System for handling document uploads and verification:

#### Document Storage Design
- Secure file storage implementation
- Document metadata management
- Version control for documents
- Access control and permissions
- Encryption for sensitive documents

#### Document Data Structure
```
document_types
├── id
├── business_id
├── name
├── description
├── required
├── expirable
├── expiration_period
├── verification_required

customer_documents
├── id
├── customer_id
├── document_type_id
├── filename
├── file_size
├── content_type
├── status
├── verified_at
├── verified_by
├── expires_at
├── created_at
├── updated_at

document_requirements
├── id
├── service_id
├── document_type_id
├── required
```

#### Document Workflow
- Upload processing pipeline
- Verification workflow
- Expiration monitoring
- Renewal notification
- Document access logging

## Development Workflow

### Rails-Specific Development Process

Structured approach to Rails development:

#### Local Development
- Docker development environment
- Database seeding with sample tenants
- Factory-based test data
- Tenant switching for local testing
- Guard for automated test running

#### Testing Strategy
- RSpec for model and controller testing
- System tests with Capybara
- FactoryBot for test data
- VCR for external API testing
- CI integration via GitHub Actions

#### Quality Assurance
- Rubocop for code quality
- Brakeman for security scanning
- Rails Best Practices enforcement
- Database consistency validation
- Cross-browser testing strategy

## Multi-Location Architecture

### Multiple Business Location Support

Design approach for businesses with multiple locations:

#### Location Data Model
- **Location Entity**: Separate model for each physical location
- **Location Relationships**: Connected to business parent
- **Location-Specific Settings**: Hours, services, staff assignments
- **Location Hierarchy**: Optional parent-child relationships
- **Geographic Data**: Coordinates, service areas, map integration

#### Multi-Location Database Design
```
locations
├── id
├── business_id
├── name
├── address
├── phone
├── email
├── latitude
├── longitude
├── timezone
├── service_radius
├── hours (jsonb)
├── status
├── parent_location_id
├── created_at
├── updated_at

location_services
├── id
├── location_id
├── service_id
├── price_override
├── duration_override
├── active

location_staff
├── id
├── location_id
├── staff_member_id
├── primary_location
├── hours (jsonb)
```

#### Location-Based Routing
- Subdomain pattern: location-business.bizblasts.com
- Location detection from URL parameters
- Geo-based location suggestion
- Default location preferences in customer profiles

## Scalability Considerations

### Rails Application Scaling

Approach to scaling the application as the business grows:

#### Initial Setup (1-50 Clients)
- Single Render web service ($7/month)
- Free tier PostgreSQL
- Efficient query optimization
- Background job prioritization
- Asset optimization

#### Growth Phase (50-200 Clients)
- Upgraded Render database plan
- Increased web service resources
- Redis for caching
- Performance monitoring implementation
- Database query optimization

#### Scale Phase (200+ Clients)
- Multiple web servers with load balancing
- Database read replicas
- Dedicated background job processing
- Content delivery network integration
- Potential service extraction for high-load components

## Technical Debt Management

### Rails Application Maintenance

Strategies for maintaining code quality over time:

#### Code Organization
- Proper use of Rails conventions
- Service objects for complex business logic
- Concerns for shared behavior
- Query objects for complex database operations
- Presenter objects for view logic

#### Refactoring Strategy
- Regular dependency updates
- Scheduled technical debt sprints
- Test coverage requirements
- Performance benchmark maintenance
- Regular security updates

## Mobile Experience Enhancement

### Mobile-Optimized Approach

Providing excellent mobile experience for both businesses and their customers:

#### Responsive Design System
- Mobile-first design methodology
- Touch-friendly interface elements
- Simplified mobile navigation
- Optimized form inputs for mobile
- Fast loading mobile experience

#### Progressive Web App Features
- Offline capabilities for critical functions
- Home screen installation
- Push notifications
- Responsive images
- Minimal data usage options

## Integration Strategy

### Third-Party Service Integrations

Key integrations to enhance platform functionality:

#### Calendar Integrations
- Google Calendar two-way sync
- iCal export/import
- Microsoft Outlook integration
- Calendar subscription feeds

#### Payment Gateways
- Stripe primary integration
- PayPal secondary option
- ACH payment support
- Saved payment methods

#### Social Media Platforms
- Facebook page integration
- Instagram feed display
- Twitter widget
- Review aggregation

#### Communication Channels
- Email notifications via SMTP
- SMS via Twilio
- WhatsApp Business integration
- Automated reminder system

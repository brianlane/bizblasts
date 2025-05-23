# BizBlasts: Rails Getting Started Checklist (Enhanced)

## Week 1: Rails Foundation Setup
- [ X ] Register bizblasts.com domain name ($12)
- [ X ] Create GitHub repository for Rails application
        - https://github.com/brianlane/bizblasts
- [ X ] Set up Ruby on Rails 8.0.2 application
- [ X ] Create Render account and configure web service ($7/month)
        - bizblasts.onrender.com
- [ X ] Set up free PostgreSQL database on Render
        - bizblast-postgresql
- [ X ] Add Devise gem for authentication
- [ X ] Add acts_as_tenant gem for multi-tenancy
- [ X ] Create initial database migrations
- [ X ] Set up GitHub Actions for CI/CD
- [ X ] Configure Render deployment from GitHub
- [ X ] Set up basic model relationships and validations
- [ X ] Create sample data for development
- [  ] Set up Twilio account for SMS features ($10/month)
- [  ] Configure SMS notification system

## Week 1-2: Admin Dashboard & Templates
- [ X ] Add ActiveAdmin gem for admin interface
- [ X ] Set up admin user authentication and authorization
- [ X ] Create business management admin panels
- [  ] Build template management system
- [ X ] Set up multi-tenant architecture
- [ X ] Create subdomain routing with acts_as_tenant gem
- [ X ] Implement site scaffolding for client websites
- [ X ] Add CSS for responsive design
- [ X ] Build core layouts and components
- [  ] Create Phoenix-focused landscaping template
- [  ] Create Phoenix-focused pool service template
- [  ] Create general service business template
- [  ] Set up asset pipeline for optimal performance
- [  ] Implement custom domain configuration
- [  ] Add ActiveStorage image upload support for Service model in ActiveAdmin (has_many_attached :images)
- [ X ] Add service type (Standard/Experience) fields and booking parameters (min_bookings, max_bookings) in ActiveAdmin service forms
- [  ] Create business analytics dashboard

## Week 2-3: Enhanced Booking System Development
- [ X ] Create service management system
- [ X ] Add 'quantity' attribute to Booking model and implement booking quantity input in public and admin forms
- [ X ] Integrate service types (Standard/Experience) with min_bookings, max_bookings, and spots management in Service model
- [  ] Add ActiveStorage image uploads and management for services (has_many_attached :images)
- [ X ] Implement staff/employee management
- [ X ] Build availability calendar system
- [ X ] Develop online booking interface
- [ X ] Create appointment management system
- [  ] Implement SMS appointment reminders
- [  ] Build calendar synchronization (Google, iCal)
- [ X ] Create customer database and profiles
- [  ] Implement booking confirmation emails
- [  ] Develop booking analytics dashboard
- [ X ] Create custom booking fields capability
- [  ] Implement recurring appointment options
- [  ] Build group booking functionality
- [  ] Develop resource allocation system
- [ X ] Create multi-location architecture
- [  ] Implement advanced intake forms with conditional logic
- [  ] Build document upload and verification system
- [  ] Develop location-specific service configuration
- [  ] Implement location-based staff assignment

## Week 3: Marketing and Payment Features
- [  ] Add Stripe gem for payment processing
- [ X ] Design and create `Product`, `Order`, `LineItem` models and migrations.
- [ X ] Build `ProductsController` and views for product display.
- [ X ] Implement basic cart logic (session or DB based) for standalone orders and booking add-ons.
- [ X ] Build `OrdersController` for standalone order creation/viewing.
- [ X ] Integrate product selection into Booking flow to add `LineItem`s to `Invoice`.
- [ X ] Create ActiveAdmin interface for `Product` and `Order` management (mirroring `Service`).
- [ X ] Implement manual shipping/tax input fields for businesses.
- [  ] Create promotional coupon system
- [  ] Implement customer loyalty tracking
- [  ] Build referral program functionality

## Week 4: Testing, Optimization & Launch
- [ X ] Write model, controller, and integration tests
- [ X ] Include testing for custom Product, Order, Cart, and Invoice logic.
- [ X ] Set up RSpec and FactoryBot for testing
- [ X ] Implement system tests with Capybara
- [ X ] Create test tenants for multi-tenant testing
- [  ] Set up performance monitoring
- [  ] Optimize database queries and indexing
- [  ] Implement caching strategies
- [  ] Set up error tracking
- [  ] Create comprehensive documentation
- [  ] Develop client onboarding guides
- [  ] Build demonstration sites for sales
- [  ] Prepare Phoenix-focused sales materials
- [  ] Test subdomain and custom domain setup
- [ X ] Configure production environment
- [  ] Launch platform with initial demo sites
- [  ] Test SMS delivery and reliability
- [  ] Verify mobile responsiveness across devices
- [  ] Test marketing feature functionality

## First Client Acquisition (Week 5)
- [  ] Attend first Phoenix networking event
- [  ] Make direct outreach calls to potential clients
- [  ] Schedule first client consultation meeting
- [  ] Create first client website using Rails platform
- [  ] Set up client's subdomain and configuration
- [  ] Configure client's booking system with services and staff
- [  ] Set up SMS reminder system for appointments
- [  ] Configure marketing features and promotions
- [  ] Train client on dashboard and booking management
- [  ] Get feedback and testimonial from first client
- [  ] Use first client as case study for future sales
- [  ] Implement improvements based on initial feedback
- [  ] Track booking system usage and effectiveness
- [  ] Monitor SMS delivery and response rates

## Initial Growth Activities (Week 6+)
- [  ] Join Phoenix-area Facebook groups for small businesses
- [  ] Create professional profiles on local business platforms
- [  ] Prepare elevator pitch for networking events
- [  ] Design simple business card (print only if needed)
- [  ] Develop referral system with Rails tracking
- [  ] Create email templates for follow-up communications
- [  ] Plan weekly schedule for Phoenix networking activities
- [  ] Implement Rails blog for content marketing
- [  ] Add client success stories to website
- [  ] Monitor usage patterns to identify improvement opportunities
- [  ] Track booking system conversion rates
- [  ] Analyze marketing feature effectiveness
- [  ] Develop mobile-focused promotional materials
- [  ] Create SMS effectiveness case studies
- [  ] Track no-show reduction statistics
- [  ] Develop client ROI calculation tools

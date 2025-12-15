# BizBlasts - Feature Requirements

## Core Platform Features

### 1. Website Creation & Management (Admin)
| Feature | Priority | Description |
|---------|----------|-------------|
| Admin Dashboard | High | Central management console for all client websites |
| Industry Templates | High | Pre-designed website templates for different service industries |
| Custom Domain Setup | High | Ability to connect purchased domains to client websites |
| Subdomain Management | High | Create and manage free-tier subdomains (business.bizblasts.com) |
| Content Management | High | Tools to create/update business information and content |
| Multi-site Overview | High | Health monitoring and statistics for all active websites |
| Performance Tracking | Medium | Website speed and visitor metrics across all sites |
| Bulk Updates | Medium | Apply changes across multiple sites (e.g., feature rollouts) |
| Client Access Control | Medium | Manage what features each client can access |
| Rails Admin Interface | High | ActiveAdmin dashboards for comprehensive management |
| Multi-Tenant Control | High | Tenant switching and management capabilities |
| Analytics Dashboard | High | Business performance metrics and reporting |

### 2. Client Website Features
| Feature | Priority | Description |
|---------|----------|-------------|
| Responsive Design | High | Mobile-friendly website layouts |
| Service Showcase | High | Display services, pricing, and business information, now includes displaying service type, type-specific booking details (min/max bookings, spots) for 'Experience' services, and the primary service image. Each service listing links to a dedicated service detail page. |
| Contact Forms | High | Allow potential customers to reach the business |
| Photo Gallery | High | Display work samples and business images |
| Testimonials Section | Medium | Showcase client reviews and feedback |
| About Us Page | Medium | Business story, team, and credentials |
| Google Maps Integration | Medium | Display business location |
| SEO Optimization | High | Meta tags, sitemap, and SEO best practices |
| Social Media Integration | Medium | Connect to business social accounts |
| Local Business Schema | High | Structured data for local businesses |
| Client Login Area | Medium | Customer account access |
| Review Collection | Medium | Tools to gather and display customer reviews |
| Service Detail Pages | High | Dedicated public pages for individual services displaying full details, images, and a booking link. |

### 3. Enhanced Booking System
| Feature | Priority | Description |
|---------|----------|-------------|
| Service Catalog | High | Define available services and durations, now includes support for different service types ('Standard' and 'Experience') with type-specific booking parameters (min_bookings, max_bookings, and spots for 'Experience' services). |
| Multiple Staff Support | High | Staff profiles, availability and assignment |
| Online Booking | High | Customer self-service appointment booking, includes support for booking quantity for 'Experience' services. |
| Calendar View | High | Visual calendar of all appointments |
| Booking Confirmation | High | Automated emails for booking confirmations |
| SMS Reminders | High | Text message reminders for appointments |
| Custom Fields | Medium | Configurable fields for booking form |
| Group Bookings | Medium | Support for classes and multi-person bookings |
| Recurring Appointments | Medium | Support for regular service scheduling |
| Buffer Times | Medium | Setup time between appointments |
| Resource Management | High | Track equipment and room usage |
| Calendar Integrations | High | Sync with Google Calendar, Outlook |
| Customer Profiles | High | Customer history and preferences |
| Multiple Locations | Medium | Support for businesses with multiple locations |
| Advanced Intake Forms | Medium | Detailed forms with conditional logic |
| Document Collection | Low | Allow file uploads for required documentation |
| Custom Notification Content | Medium | Personalized message templates for communications |
| Service Packages | Medium | Bundled services with special pricing |
| Service Image Support | High | Allow businesses to upload and manage images for services, including setting a primary image. |

### 4. Marketing Tools
| Feature | Priority | Description |
|---------|----------|-------------|
| Promotional Coupons | High | Create and manage discount codes |
| Loyalty Program | Medium | Customer rewards and points system |
| Referral System | Medium | Track and reward client referrals |
| Email Campaigns | High | Simple email marketing tools |
| Social Media Sharing | Medium | Easy sharing of promotions |
| Gift Cards | Low | Digital gift card creation and redemption |
| Special Offers | Medium | Limited-time discounts and packages |
| Seasonal Promotions | Medium | Holiday and event-based marketing |
| Campaign Analytics | Medium | Track marketing effectiveness |
| Automated Follow-ups | High | Post-service emails and offers |
| Abandoned Booking Recovery | Medium | Remind customers of incomplete bookings |

### 5. Payment Processing
| Feature | Priority | Description |
|---------|----------|-------------|
| Stripe Integration | High | Credit card payment processing |
| Transaction Fee Structure | High | Configurable fee percentages based on tier |
| Payment Dashboard | High | Overview of all transactions and fees |
| ACH Support | Medium | Bank transfer payments (Premium tier) |
| Subscription Billing | Medium | Recurring payment management |
| Partial Payments | Medium | Deposits and installment options |
| Payment Links | Medium | Shareable links for remote payments |
| Multi-currency Support | Low | Support for businesses serving international customers |
| Saved Payment Methods | Medium | Store payment information for returning customers |
| Automatic Receipts | High | Email receipts after payment |
| Refund Processing | Medium | Handle refunds and cancelations |

### 6. Client Communication System
| Feature | Priority | Description |
|---------|----------|-------------|
| Email Notifications | High | Automated emails for various events |
| SMS Messaging | High | Text message alerts and reminders |
| Customizable Templates | High | Email and SMS message templates |
| Two-way Messaging | Medium | Client-business communication |
| Chat Widget | Medium | Website chat for customer questions |
| Notification Preferences | Medium | Client communication preferences |
| Automated Sequences | Medium | Pre-defined communication workflows |
| Message History | Medium | Record of all client communications |
| Mass Announcements | Low | Send messages to all clients |
| Feedback Collection | High | Post-service feedback requests |
| Reply Tracking | Medium | Monitor client responses |

### 7. Product Management (Custom Implementation)
| Feature | Priority | Description |
|---------|----------|-------------|
| Core Product System | High | Create and manage products, separate from services (using custom `Product` model). |
| Standalone & Add-on Products | High | Support products sold independently (via `Order`) and as add-ons during service booking (via `Invoice`/`LineItem`). |
| Basic Inventory | Medium | Basic stock tracking per product (potential for future `ProductVariant` model). |

| Standalone Order Cart | High | Cart functionality for standalone product purchases, leading to an `Order` record. |
| Standalone Order Checkout | High | Basic checkout flow for standalone product `Order`s (Payment integration TBD). |
| Add-on Selection (Booking) | High | Interface to add products to a service `Booking`, updating the associated `Invoice`'s `LineItem`s. |
| Shipping Info Capture | High | Capture customer shipping address; allow businesses to manually define shipping methods/costs per order/invoice. |
| Pickup Option | Medium | Allow customers to select in-store pickup (simple flag/method). |
| Product Display (Grid) | High | Grid view for product listings with filtering. |
| Product Detail Pages | High | Dedicated pages for individual products. |
| Order Management (Standalone) | High | Track and manage customer orders for standalone product purchases (custom `Order` model). |
| Invoice Management (Integrated) | High | Track and manage invoices including booked services and added products (existing `Invoice` model with `LineItem`s). |
| Tax Info Capture | High | Allow businesses to manually input tax amounts per order/invoice. |
| Admin Product Management | High | CRUD operations for `Product` model in ActiveAdmin (mirroring `Service` admin). |
| Admin Inventory Management | Medium | Admin interface for managing basic stock levels per `Product`. |

| Admin Order Viewing | High | Admins can view/manage standalone product `Order`s across tenants. |
| Admin Invoice Viewing | High | Admins can view/manage `Invoice`s (including products) across tenants. |
| Business Owner Product Mgmt | High | Interface for business owners to manage their own `Product`s. |
| Business Owner Inventory Mgmt | Medium | Interface for business owners to manage basic stock for their `Product`s. |
| Business Owner Order Mgmt | High | Interface for business owners to view/manage their standalone product `Order`s. |
| Business Owner Invoice Mgmt | High | Interface for business owners to view/manage their `Invoice`s (including products). |
| Product Sales Reports | Medium | Basic analytics and reports for product sales (custom reports based on `Order` and `Invoice`/`LineItem` data). |
| Link Goods to Services | High | Mechanism for business owners/admins to associate goods as potential add-ons for specific services. |

### 9. Multi-Location Support
| Feature | Priority | Description |
|---------|----------|-------------|
| Location Management | Medium | Add and manage multiple business locations |
| Location-Based Services | Medium | Configure different services by location |
| Location-Specific Staff | Medium | Assign staff members to specific locations |
| Location Calendar | Medium | Separate booking calendars by location |
| Location Hours | Medium | Different business hours by location |
| Location Analytics | Medium | Performance metrics split by location |
| Geographic Service Areas | Medium | Define service coverage zones by location |
| Location Selection | Medium | Allow customers to choose preferred location |
| Location-Specific Pricing | Low | Different pricing structures by location |
| Map Integration | Medium | Visual map of all business locations |
| Directions | Low | Automated directions to each location |
| Location Search | Low | Find nearest location based on customer address |

### 10. Document Verification & Collection
| Feature | Priority | Description |
|---------|----------|-------------|
| Document Upload | Medium | Allow clients to upload required documents |
| Document Types | Low | Configure various document type requirements |
| Document Verification | Low | Manual review and approval workflow |
| Document Storage | Medium | Secure storage of client documents |
| Document Expiration | Low | Track document validity and expiration |
| Required Documents | Medium | Link document requirements to services |
| Document Templates | Low | Provide fillable templates for clients |
| Document Notifications | Low | Reminders for missing or expiring documents |
| Document Access Control | Medium | Permission-based access to sensitive documents |
| Document Categories | Low | Organize documents by type and purpose |
| Compliance Management | Low | Track regulatory requirements for documents |

## Tiered Feature Availability

### Free Tier ($0/month + Transaction Fees)
- BizBlasts subdomain (business.bizblasts.com)
- Basic responsive website
- Online scheduling (client manages availability)
- Basic invoicing
- Payment processing (5% transaction fee + Stripe fees)
- Email support (48-hour response time)
- Email notifications
- Basic business analytics
- Mobile-responsive design

### Standard Tier ($49/month + Reduced Transaction Fees)
- Custom domain
- Enhanced website design
- All Free tier features
- Multiple staff support (1-3 staff members)
- SMS appointment reminders (limited monthly)
- Reduced transaction fees (3% + Stripe fees)
- Additional service pages
- Enhanced analytics
- Email support (24-hour response time)
- Monthly site updates (1 per month)
- Google Calendar integration
- Basic promotional tools
- Custom booking fields
- Customer profiles

### Premium Tier ($99/month + Minimal Transaction Fees)
- Custom domain support (you provide your own domain)*
- Premium website design
- All Standard tier features
- Unlimited staff members
- Unlimited SMS reminders
- Minimal transaction fees (1% + Stripe fees)
- Priority support (same-day response)
- Advanced analytics dashboard
- ACH payment support
- Full marketing suite
- Customer loyalty program
- Monthly site updates (3 per month)
- Emergency support
- Custom email and SMS templates
- Two-way messaging with clients
- Advanced reporting
- Resource management
- Group booking capabilities

*Custom Domain Policy: BizBlasts provides custom domain setup and SSL certificate management at no additional cost. Customers are responsible for purchasing and renewing their own domain from a domain registrar of their choice. BizBlasts handles the technical setup including DNS configuration, SSL certificates, and domain verification.

## Add-On Features (Additional Cost)
- Additional site updates: $50 per update
- Custom development: Quote-based
- SEO package: $75/month
- Email marketing campaign: $25/month
- Review management system: $15/month
- Additional staff accounts: $5/user/month
- Advanced integration setup: $100 one-time

## Technical Requirements
- 99.9% uptime SLA
- Mobile-responsive designs
- Sub-3 second page load times
- PCI DSS compliance for payment processing
- GDPR and CCPA data privacy compliance
- Regular security audits
- Automated backups
- Cross-browser compatibility
- Accessibility compliance
- SMS delivery reliability
- Email deliverability monitoring
- Seamless calendar syncing
- PDF generation for invoices and reports

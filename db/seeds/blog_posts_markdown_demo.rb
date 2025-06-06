demo_post = BlogPost.create!(
  title: "Markdown Formatting Guide for BizBlasts Blog",
  slug: "markdown-formatting-guide",
  author_name: "BizBlasts Team",
  author_email: "team@bizblasts.com",
  category: "tutorial",
  excerpt: "Learn how to use **Markdown** and HTML formatting in BizBlasts blog posts. This guide covers everything from basic text formatting to advanced features like code blocks and tables.",
  content: <<~MARKDOWN,
    # Complete Markdown Guide

    This post demonstrates all the **Markdown** and HTML formatting features available in BizBlasts blog posts.

    ## Text Formatting

    You can make text **bold** or *italic*, or even ***both***. You can also ~~strike through~~ text.

    ### Links and References

    Create [inline links](https://bizblasts.com) or reference-style links like [this one][1].

    [1]: https://docs.bizblasts.com

    ## Code Examples

    ### Inline Code

    Use `inline code` for short snippets like `const greeting = "Hello World"`.

    ### Code Blocks with Syntax Highlighting

    ```javascript
    // JavaScript example
    function calculateBookingCost(service, duration) {
      const hourlyRate = service.hourlyRate;
      const totalCost = hourlyRate * duration;
      
      return {
        subtotal: totalCost,
        tax: totalCost * 0.08,
        total: totalCost * 1.08
      };
    }
    ```

    ```ruby
    # Ruby on Rails example
    class BookingController < ApplicationController
      before_action :authenticate_user!
      
      def create
        @booking = current_user.bookings.build(booking_params)
        
        if @booking.save
          BookingMailer.confirmation(@booking).deliver_later
          redirect_to @booking, notice: 'Booking created successfully!'
        else
          render :new
        end
      end
      
      private
      
      def booking_params
        params.require(:booking).permit(:service_id, :date, :time, :duration)
      end
    end
    ```

    ```sql
    -- SQL Query example
    SELECT 
      b.id,
      b.scheduled_date,
      s.name AS service_name,
      u.email AS customer_email,
      b.total_amount
    FROM bookings b
    JOIN services s ON b.service_id = s.id
    JOIN users u ON b.user_id = u.id
    WHERE b.status = 'confirmed'
      AND b.scheduled_date >= CURRENT_DATE
    ORDER BY b.scheduled_date ASC;
    ```

    ## Lists

    ### Unordered Lists

    - Service business management
    - Customer booking system
    - Payment processing
      - Stripe integration
      - Invoice generation
      - Recurring payments
    - Staff scheduling
    - Inventory tracking

    ### Ordered Lists

    1. Create your business profile
    2. Set up your services
    3. Configure booking availability
    4. Launch your booking page
    5. Start accepting bookings!

    ## Tables

    | Feature | Basic Plan | Pro Plan | Enterprise |
    |---------|------------|----------|------------|
    | Bookings/month | 100 | 1,000 | Unlimited |
    | Staff members | 3 | 10 | Unlimited |
    | Custom branding | ❌ | ✅ | ✅ |
    | API access | ❌ | ❌ | ✅ |
    | Priority support | ❌ | ✅ | ✅ |

    ## Blockquotes

    > "BizBlasts has completely transformed how we manage our landscaping business. The booking system is intuitive, and our customers love the convenience of online scheduling."
    > 
    > — Sarah Martinez, GreenScape Landscaping

    ## Images

    ![BizBlasts Dashboard](https://via.placeholder.com/600x300/4F46E5/FFFFFF?text=BizBlasts+Dashboard)

    ## Advanced Features

    ### Nested Lists with Mixed Types

    1. **Service Setup**
       - Define service categories
       - Set pricing tiers
       - Configure duration options
    2. **Staff Management**
       - Add team members
       - Set availability schedules
       - Assign service permissions
    3. **Customer Experience**
       - Branded booking pages
       - Automated confirmations
       - SMS reminders

    ### Code with Multiple Languages

    Here's how to integrate our webhook system:

    ```bash
    # Install the webhook handler
    npm install @bizblasts/webhook-handler
    ```

    ```python
    # Python webhook handler
    from flask import Flask, request
    import bizblasts_webhooks

    app = Flask(__name__)

    @app.route('/webhooks/bizblasts', methods=['POST'])
    def handle_webhook():
        payload = request.json
        event_type = payload.get('event_type')
        
        if event_type == 'booking.created':
            # Handle new booking
            booking_data = payload['data']
            send_internal_notification(booking_data)
            
        return {'status': 'success'}
    ```

    ## HTML Support

    You can also use HTML tags when needed:

    <div class="alert alert-info">
      <strong>Pro Tip:</strong> Combine Markdown with HTML for maximum flexibility!
    </div>

    <details>
    <summary>Click to expand advanced configuration</summary>
    
    This section contains advanced configuration options that are typically only needed for enterprise customers.
    
    </details>

    ## Footnotes

    BizBlasts supports over 50 different service industries[^1] and processes thousands of bookings daily[^2].

    [^1]: Including but not limited to: landscaping, cleaning, tutoring, fitness training, and consulting.
    [^2]: Our system handles peak loads of over 10,000 concurrent bookings during busy seasons.

    ---

    *That's everything you need to know about Markdown formatting in BizBlasts blog posts!*
  MARKDOWN
  featured_image_url: "https://via.placeholder.com/800x400/4F46E5/FFFFFF?text=Markdown+Guide",
  published: true,
  published_at: 1.hour.ago
)

puts "Created Markdown demo post: #{demo_post.title}" 
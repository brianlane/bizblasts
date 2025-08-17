# BizBlasts QR Code Payment Collection - Implementation Plan (REVISED)

**Created:** 2025-08-15  
**Updated:** 2025-08-15  
**Owner:** Claude Code AI  
**Status:** PIVOT - Revised for BizBlasts URL QR Codes

---

## 1. Overview

**REVISED APPROACH:** After consultation with Stripe, Payment Links cannot support application fees on Standard connected accounts (required for BizBlasts tax liability). 

**NEW SOLUTION:** Generate QR codes that link directly to the existing BizBlasts invoice payment view - the same URLs that are already sent in invoice emails. This maintains the QR code user experience while leveraging the proven invoice payment flow with proper application fee collection.

### **Key Changes from Original Plan:**
- ❌ **Remove:** Stripe Payment Links integration (application fee incompatible)
- ❌ **Remove:** Complex payment flow with Stripe-hosted checkout
- ✅ **Keep:** QR code generation and display UI
- ✅ **Keep:** Real-time payment status polling
- ✅ **Simplify:** QR codes link to existing BizBlasts invoice URLs
- ✅ **Benefit:** Maintains application fee collection on Standard connected accounts

---

## 2. Technical Architecture

### **Leverage Existing Infrastructure**
- ✅ **Invoice payment URLs** - Already working in email flows with application fees
- ✅ **Stripe Checkout Sessions** - Existing implementation supports Standard connected accounts
- ✅ **Webhook handling** - Existing `StripeWebhooksController` 
- ✅ **Payment models** - Reuse existing `Payment`, `Order`, and `Invoice` models
- ✅ **Multi-tenant setup** - Works with existing business/subdomain structure

### **New Components Required**
- **QR Code generation** - Simple URL-to-QR conversion (no Stripe Payment Links)
- **Modal display** - Client-side QR code presentation  
- **Real-time updates** - Payment status polling using existing invoice status

---

## 3. User Experience Flow

### **Business Owner Workflow:**
1. Navigate to **Transactions** or **Invoices** page
2. Find pending invoice in list
3. Click **"Show QR Code"** button 
4. Modal opens showing large QR code + invoice details
5. Show screen to customer for scanning
6. See real-time payment confirmation when completed
7. Modal auto-closes or manual close after payment

### **Customer Workflow:**
1. See QR code on business owner's screen
2. Open camera app or QR scanner on their phone
3. Scan QR code → opens **BizBlasts invoice payment page** in their browser
4. Complete payment using existing BizBlasts/Stripe checkout flow
5. See confirmation page on their device (same as email payment flow)

---

## 4. Implementation Details

### **4.1 Backend Changes**

#### **Controller Addition:**
```ruby
# app/controllers/qr_payments_controller.rb
class QrPaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order, only: [:show, :status]
  
  def show
    # Generate QR code for order payment
    # Return QR code data URL and payment details
  end
  
  def status  
    # Check payment status for real-time updates
    # Return JSON with current order payment status
  end
  
  private
  
  def set_order
    @order = current_business.orders.find(params[:id])
  end
end
```

#### **Simplified Service Object:**
```ruby
# app/services/qr_payment_service.rb
class QrPaymentService
  def self.generate_qr_code(invoice)
    # Generate BizBlasts invoice payment URL (same as email links)
    invoice_url = build_invoice_payment_url(invoice)
    
    # Create QR code containing BizBlasts URL
    qr_code_data_url = generate_qr_code_image(invoice_url)
    
    # Return QR code data and invoice details
    {
      qr_code_data_url: qr_code_data_url,
      invoice_url: invoice_url,
      invoice_number: invoice.invoice_number,
      amount: invoice.total_amount,
      customer_name: invoice.tenant_customer.name,
      business_name: invoice.business.name
    }
  end
  
  def self.check_payment_status(invoice)
    # Use existing invoice payment status
    {
      paid: invoice.paid?,
      status: invoice.status,
      total_paid: invoice.total_paid,
      balance_due: invoice.balance_due
    }
  end
  
  private
  
  def self.build_invoice_payment_url(invoice)
    # Same URL pattern as invoice emails
    Rails.application.routes.url_helpers.tenant_invoice_url(
      invoice,
      host: invoice.business.hostname,
      protocol: 'https'
    )
  end
  
  def self.generate_qr_code_image(url)
    # Simple QR code generation for URL
    qr = RQRCode::QRCode.new(url)
    png = qr.as_png(size: 400)
    "data:image/png;base64,#{Base64.strict_encode64(png.to_s)}"
  end
end
```

#### **Routes Addition:**
```ruby
# config/routes.rb
resources :orders do
  member do
    get :qr_payment, to: 'qr_payments#show'
    get :payment_status, to: 'qr_payments#status'
  end
end
```

### **4.2 Frontend Changes**

#### **Transactions View Update:**
```erb
<!-- app/views/orders/index.html.erb -->
<% @orders.pending.each do |order| %>
  <tr>
    <!-- existing order details -->
    <td>
      <%= button_to "Display QR Code", 
          qr_payment_order_path(order), 
          method: :get, 
          remote: true,
          class: "btn btn-primary",
          data: { 
            bs_toggle: "modal", 
            bs_target: "#qrPaymentModal",
            order_id: order.id 
          } %>
      <small class="text-muted d-block">Collect payment now</small>
    </td>
  </tr>
<% end %>
```

#### **QR Code Modal:**
```erb
<!-- app/views/shared/_qr_payment_modal.html.erb -->
<div class="modal fade" id="qrPaymentModal" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title">Collect Payment</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
      </div>
      <div class="modal-body text-center">
        <div id="qr-code-container">
          <!-- QR code will be inserted here -->
        </div>
        <div id="payment-details">
          <!-- Order details and amount -->
        </div>
        <div id="payment-status" class="mt-3">
          <div class="alert alert-info">
            <i class="fas fa-qrcode"></i>
            Customer should scan this QR code with their phone camera
          </div>
        </div>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">
          Close
        </button>
      </div>
    </div>
  </div>
</div>
```

#### **Stimulus Controller:**
```javascript
// app/javascript/controllers/qr_payment_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { orderId: Number, pollInterval: Number }
  
  connect() {
    this.pollInterval = 3000 // Poll every 3 seconds
    this.startPolling()
  }
  
  disconnect() {
    this.stopPolling()
  }
  
  startPolling() {
    this.pollTimer = setInterval(() => {
      this.checkPaymentStatus()
    }, this.pollIntervalValue)
  }
  
  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer)
    }
  }
  
  async checkPaymentStatus() {
    const response = await fetch(`/orders/${this.orderIdValue}/payment_status`)
    const data = await response.json()
    
    if (data.paid) {
      this.showPaymentSuccess()
      this.stopPolling()
    }
  }
  
  showPaymentSuccess() {
    // Update modal to show success state
    // Auto-close after 3 seconds
  }
}
```

### **4.3 Dependencies**

#### **QR Code Generation:**
```ruby
# Gemfile
gem 'rqrcode', '~> 2.2'
gem 'chunky_png', '~> 1.4'
```

---

## 5. Database Changes

### **Minimal Changes Required:**
- ✅ **No new tables needed** - Leverages existing Order and Payment models
- ✅ **Existing webhook handling** - Works with current StripeWebhooksController
- ✅ **Payment Links reuse** - Uses existing Stripe Payment Link creation logic

### **Optional Enhancement:**
```ruby
# If we want to track QR code generation
add_column :orders, :qr_code_generated_at, :datetime
add_column :orders, :qr_code_scanned_at, :datetime
```

---

## 6. Implementation Phases

### **Phase 1: Core QR Code Generation (Week 1)**
- [ ] Add QR code gem dependencies
- [ ] Create `QrPaymentService` for Payment Link + QR generation  
- [ ] Create `QrPaymentsController` for modal endpoints
- [ ] Add routes for QR payment endpoints

### **Phase 2: Frontend Integration (Week 1)**  
- [ ] Add "Display QR Code" button to Transactions view
- [ ] Create QR payment modal component
- [ ] Implement basic QR code display functionality
- [ ] Test QR code scanning and payment flow

### **Phase 3: Real-time Updates (Week 2)**
- [ ] Add Stimulus controller for payment status polling
- [ ] Implement payment status endpoint
- [ ] Add success/failure state handling in modal
- [ ] Test complete end-to-end flow

### **Phase 4: Polish & Testing (Week 2)**
- [ ] Add loading states and error handling
- [ ] Implement responsive design for mobile displays  
- [ ] Add analytics tracking for QR code usage
- [ ] System testing and QA validation

---

## 7. Security Considerations

### **Payment Link Security:**
- ✅ **Stripe-hosted payment** - Customer payment happens on Stripe's secure servers
- ✅ **Time-limited links** - Payment Links can expire after set duration  
- ✅ **Single-use enforcement** - Order can only be paid once
- ✅ **Webhook validation** - Existing webhook signature verification

### **QR Code Security:**
- ✅ **Public payment URLs** - QR codes contain public Payment Link URLs (no sensitive data)
- ✅ **Business context validation** - QR generation requires authenticated business owner
- ✅ **Order ownership** - Users can only generate QR codes for their business orders

---

## 8. Success Metrics

### **Technical Success:**
- [ ] QR codes generate within 2 seconds
- [ ] Payment completion detected within 10 seconds  
- [ ] >99% uptime for QR payment flow
- [ ] Zero payment processing errors

### **User Experience Success:**
- [ ] <30 seconds total payment time (scan → completion)
- [ ] Clear visual feedback throughout process
- [ ] Intuitive UI requiring no training
- [ ] Mobile-responsive QR code display

### **Business Success:**
- [ ] Increased in-person payment collection
- [ ] Reduced manual payment entry time
- [ ] Improved customer payment experience
- [ ] Analytics on QR code usage patterns

---

## 9. Future Enhancements

### **Short-term (Next Release):**
- Multiple order selection for combined QR payments
- Custom QR code branding/styling
- SMS/email QR code sharing for remote customers

### **Long-term (Future Releases):**
- Real-time payment notifications via WebSockets
- QR code analytics dashboard
- Integration with native iOS companion app
- Support for booking and invoice QR payments

---

## 10. Implementation Effort

### **Estimated Development Time:**
- **Backend development:** 8-12 hours
- **Frontend development:** 12-16 hours  
- **Testing & integration:** 6-8 hours
- **Total:** ~25-35 hours (3-4 days)

### **Risk Assessment:**
- 🟢 **Low risk** - Builds on existing proven infrastructure
- 🟢 **No breaking changes** - Additive feature only
- 🟢 **Fallback available** - Existing email payment flow remains unchanged
- 🟡 **QR dependency** - Requires customers to have QR-capable devices (99%+ coverage)

---

## 11. Questions for Review

1. **UI Placement:** Is the Transactions view the right location for the "Display QR Code" button?

2. **Modal vs Page:** Should QR display be a modal or dedicated page for better mobile experience?

3. **Polling Frequency:** Is 3-second polling appropriate for payment status updates?

4. **Additional Views:** Should QR codes also be available for bookings and invoices, or start with orders only?

5. **Analytics:** What specific metrics should we track for QR code usage?

6. **Branding:** Should QR codes include BizBlasts branding/logo in the center?

---

*Ready for implementation upon approval*
# frozen_string_literal: true

require 'rqrcode'
require 'chunky_png'

class QrPaymentService
  # Generate QR code for invoice payment using BizBlasts invoice URLs
  
  def self.generate_qr_code(invoice)
    # Validate invoice
    raise ArgumentError, "Invoice must be present" unless invoice.present?
    raise ArgumentError, "Invoice must be pending or overdue" unless invoice.pending? || invoice.overdue?
    raise ArgumentError, "Invoice amount must be at least $0.50" if invoice.total_amount < 0.50
    
    # Generate BizBlasts invoice payment URL with token
    invoice_url = build_invoice_payment_url(invoice)
    
    # Generate QR code with BizBlasts branding
    qr_data_url = generate_qr_code_image(invoice_url, invoice.business.name)
    
    # Track QR code generation
    track_qr_generation(invoice)
    
    {
      qr_code_data_url: qr_data_url,
      payment_link_url: invoice_url,
      amount: invoice.total_amount,
      invoice_number: invoice.invoice_number,
      customer_name: invoice.tenant_customer.full_name,
      business_name: invoice.business.name
    }
  rescue => e
    Rails.logger.error "[QR_PAYMENT] Failed to generate QR code for invoice #{invoice&.id}: #{e.message}"
    raise
  end
  
  def self.check_payment_status(invoice)
    {
      paid: invoice.paid?,
      status: invoice.status,
      total_paid: invoice.total_paid,
      balance_due: invoice.balance_due,
      last_updated: Time.current
    }
  end
  
  private
  
  def self.build_invoice_payment_url(invoice)
    # Generate the same tokenized URL that customers receive in emails (matching InvoiceMailer)
    url_options = {
      token: invoice.guest_access_token,
      subdomain: invoice.business.hostname,
      host: Rails.application.config.action_mailer.default_url_options[:host],
      protocol: Rails.env.development? ? 'http' : 'https'
    }
    
    # Include port in development
    if Rails.env.development? && Rails.application.config.action_mailer.default_url_options[:port]
      url_options[:port] = Rails.application.config.action_mailer.default_url_options[:port]
    end
    
    Rails.application.routes.url_helpers.tenant_invoice_url(invoice, url_options)
  end
  
  def self.generate_qr_code_image(url, business_name)
    # Create QR code
    qr = RQRCode::QRCode.new(url, size: 10, level: :l)
    
    # Generate PNG with higher resolution for better scanning
    png = qr.as_png(
      resize_gte_to: false,
      resize_exactly_to: 400,
      fill: 'white',
      color: 'black',
      border_modules: 4
    )
    
    # Add BizBlasts branding in center
    branded_png = add_branding_to_qr(png, business_name)
    
    # Convert to data URL
    "data:image/png;base64,#{Base64.strict_encode64(branded_png.to_s)}"
  end
  
  def self.add_branding_to_qr(png_data, business_name)
    # Load the QR code image
    image = ChunkyPNG::Image.from_blob(png_data.to_s)
    
    # Calculate center position for logo area
    width = image.width
    height = image.height
    center_x = width / 2
    center_y = height / 2
    logo_size = [width / 6, 40].max # At least 40px, or 1/6 of QR width
    
    # Create white background circle for logo area
    logo_radius = logo_size / 2
    
    (center_y - logo_radius..center_y + logo_radius).each do |y|
      (center_x - logo_radius..center_x + logo_radius).each do |x|
        # Check if pixel is within circle
        distance = Math.sqrt((x - center_x) ** 2 + (y - center_y) ** 2)
        if distance <= logo_radius
          image[x, y] = ChunkyPNG::Color::WHITE
        end
      end
    end
    
    # Add simple "B" text for BizBlasts branding
    # Note: This is a simple implementation. For production, consider using ImageMagick or similar
    add_simple_logo_text(image, center_x, center_y, logo_size)
    
    image.to_blob
  end
  
  def self.add_simple_logo_text(image, center_x, center_y, logo_size)
    # Simple "B" letter implementation using pixels
    # This creates a basic "B" shape in the center
    text_size = [logo_size / 3, 12].max
    color = ChunkyPNG::Color::BLACK
    
    # Vertical line of "B"
    (center_y - text_size/2..center_y + text_size/2).each do |y|
      image[center_x - text_size/4, y] = color if y >= 0 && y < image.height && center_x - text_size/4 >= 0
    end
    
    # Top horizontal line
    (center_x - text_size/4..center_x + text_size/6).each do |x|
      image[x, center_y - text_size/2] = color if x >= 0 && x < image.width && center_y - text_size/2 >= 0
      image[x, center_y] = color if x >= 0 && x < image.width && center_y >= 0
      image[x, center_y + text_size/2] = color if x >= 0 && x < image.width && center_y + text_size/2 < image.height
    end
  end
  
  def self.track_qr_generation(invoice)
    # Simple tracking - could be enhanced with dedicated analytics table
    Rails.logger.info "[QR_PAYMENT] QR code generated for invoice #{invoice.id} (#{invoice.invoice_number}) - Business: #{invoice.business.name}"
    
    # Update invoice with QR generation timestamp if column exists
    if invoice.respond_to?(:qr_code_generated_at=)
      invoice.update_column(:qr_code_generated_at, Time.current)
    end
  end
end
# Generates PDF for estimates using Prawn gem
# Matches minimal professional design with white background
# BizBlasts brand colors used sparingly: Primary #1A5F7A, Secondary #57C5B6
class EstimatePdfGenerator
  require 'prawn'
  require 'prawn/table'

  # BizBlasts brand colors (converted to Prawn hex format)
  BRAND_PRIMARY = '1A5F7A'    # Teal blue - used for headings and accent lines
  BRAND_SECONDARY = '57C5B6'  # Light teal - used sparingly for highlights
  TEXT_DARK = '333333'        # Dark gray for body text
  TEXT_LIGHT = '666666'       # Light gray for secondary text
  BORDER_COLOR = 'E5E7EB'     # Light gray for table borders

  def initialize(estimate)
    @estimate = estimate
    @business = estimate.business
  end

  def generate
    pdf = Prawn::Document.new(
      page_size: 'LETTER',
      margin: 50
    )

    build_pdf(pdf)

    # Attach to estimate
    @estimate.pdf.attach(
      io: StringIO.new(pdf.render),
      filename: "#{@estimate.estimate_number || 'estimate'}.pdf",
      content_type: 'application/pdf'
    )

    @estimate.update(pdf_generated_at: Time.current)

    pdf
  end

  private

  def build_pdf(pdf)
    add_header(pdf)
    add_estimate_info(pdf)
    add_client_info(pdf)
    add_line_items(pdf)
    add_totals(pdf)
    add_payment_terms(pdf) if @estimate.required_deposit.present? && @estimate.required_deposit > 0
    add_signature_section(pdf)
    add_footer(pdf)
  end

  def add_header(pdf)
    # Business name on left, estimate number on right
    pdf.font_size(20) do
      pdf.text @business.name, style: :bold, color: BRAND_PRIMARY
    end

    # Business contact info (smaller, light gray)
    pdf.move_down 5
    pdf.font_size(9) do
      contact_lines = []
      contact_lines << @business.address if @business.address.present?
      contact_lines << "#{@business.city}, #{@business.state} #{@business.zip}" if @business.city.present?
      contact_lines << @business.phone if @business.phone.present?
      contact_lines << @business.email if @business.email.present?
      pdf.text contact_lines.join(' | '), color: TEXT_LIGHT
    end

    # Estimate number - prominent on right side
    pdf.move_up 40
    pdf.text_box "ESTIMATE",
      at: [pdf.bounds.width - 200, pdf.cursor + 30],
      width: 200,
      size: 10,
      style: :bold,
      align: :right,
      color: TEXT_LIGHT

    pdf.text_box @estimate.estimate_number || 'Draft',
      at: [pdf.bounds.width - 200, pdf.cursor + 15],
      width: 200,
      size: 14,
      style: :bold,
      align: :right,
      color: BRAND_PRIMARY

    pdf.move_down 30

    # Horizontal line
    pdf.stroke_color BRAND_PRIMARY
    pdf.line_width 2
    pdf.stroke_horizontal_line 0, pdf.bounds.width
    pdf.move_down 20
  end

  def add_estimate_info(pdf)
    data = [
      ["Date:", @estimate.created_at.strftime('%B %d, %Y')],
      ["Valid Until:", (@estimate.created_at + @estimate.valid_for_days.days).strftime('%B %d, %Y')]
    ]

    if @estimate.proposed_start_time.present?
      data << ["Proposed Start:", @estimate.proposed_start_time.strftime('%B %d, %Y')]
    end

    if @estimate.approved_at.present?
      data << ["Approved:", @estimate.approved_at.strftime('%B %d, %Y')]
    end

    pdf.table(data,
      cell_style: { borders: [], padding: [2, 0], size: 10 },
      column_widths: [100, 200]
    ) do
      column(0).font_style = :bold
      column(0).text_color = TEXT_LIGHT
      column(1).text_color = TEXT_DARK
    end

    pdf.move_down 20
  end

  def add_client_info(pdf)
    pdf.font_size(11) do
      pdf.text "PREPARED FOR", style: :bold, color: BRAND_PRIMARY
    end
    pdf.move_down 5

    # Draw a thin accent line
    pdf.stroke_color BRAND_SECONDARY
    pdf.line_width 1
    pdf.stroke_horizontal_line 0, 150
    pdf.move_down 8

    pdf.font_size(10) do
      pdf.text @estimate.customer_full_name, style: :bold, color: TEXT_DARK
      pdf.text @estimate.full_address, color: TEXT_DARK if @estimate.address.present?
      pdf.text @estimate.customer_email, color: TEXT_LIGHT
      pdf.text @estimate.customer_phone, color: TEXT_LIGHT if @estimate.customer_phone.present?
    end

    pdf.move_down 25
  end

  def add_line_items(pdf)
    pdf.font_size(11) do
      pdf.text "LINE ITEMS", style: :bold, color: BRAND_PRIMARY
    end
    pdf.move_down 5

    # Draw a thin accent line
    pdf.stroke_color BRAND_SECONDARY
    pdf.line_width 1
    pdf.stroke_horizontal_line 0, 100
    pdf.move_down 10

    # Required items
    required_items = @estimate.estimate_items.required.by_position
    add_items_table(pdf, required_items) if required_items.any?

    # Optional items (if any) - all items shown, declined marked as such
    if @estimate.has_optional_items?
      pdf.move_down 15
      pdf.font_size(10) do
        pdf.text "OPTIONAL ITEMS", style: :bold, color: TEXT_LIGHT
      end
      pdf.move_down 5

      optional_items = @estimate.estimate_items.optional_items.by_position
      add_items_table(pdf, optional_items, show_status: true)
    end
  end

  def add_items_table(pdf, items, show_status: false)
    return if items.empty?

    headers = ["Description", "Qty", "Rate", "Total"]
    headers << "Status" if show_status

    table_data = [headers]

    items.each do |item|
      row = [
        item.display_name.to_s.truncate(50),
        item.qty.to_s,
        format_currency(item.cost_rate),
        format_currency(item.total)
      ]

      if show_status
        if item.customer_declined?
          row << "DECLINED"
        elsif item.customer_selected?
          row << "SELECTED"
        else
          row << "PENDING"
        end
      end

      table_data << row
    end

    col_widths = show_status ? [200, 50, 80, 80, 80] : [250, 50, 100, 100]

    pdf.table(table_data,
      header: true,
      column_widths: col_widths,
      cell_style: {
        padding: [8, 6],
        borders: [:bottom],
        border_width: 0.5,
        border_color: BORDER_COLOR,
        size: 9
      }
    ) do |table|
      table.row(0).font_style = :bold
      table.row(0).background_color = 'F9FAFB'
      table.row(0).text_color = TEXT_DARK
      table.row(0).borders = [:bottom]
      table.row(0).border_width = 1
      table.row(0).border_color = BORDER_COLOR

      # Right align numeric columns (qty, rate, total)
      table.columns(1..3).align = :right

      # Center align status column if present
      if show_status
        table.columns(4).align = :center
      end
    end
  end

  def add_totals(pdf)
    pdf.move_down 20

    # Calculate totals excluding declined items
    included_items = @estimate.items_for_calculation
    subtotal = included_items.sum { |item| item.total.to_d }
    taxes = included_items.sum { |item| item.tax_amount.to_d }
    total = subtotal + taxes

    totals_data = [
      ["Subtotal:", format_currency(subtotal)],
      ["Taxes:", format_currency(taxes)],
      ["TOTAL:", format_currency(total)]
    ]

    if @estimate.required_deposit.present? && @estimate.required_deposit > 0
      totals_data << ["", ""]
      totals_data << ["Deposit Required:", format_currency(@estimate.required_deposit)]
      remaining = total - @estimate.required_deposit
      totals_data << ["Balance Due:", format_currency(remaining)]
    end

    has_deposit = @estimate.required_deposit.present? && @estimate.required_deposit > 0

    pdf.table(totals_data,
      position: :right,
      column_widths: [120, 100],
      cell_style: {
        borders: [],
        padding: [4, 6],
        size: 10,
        align: :right
      }
    ) do |table|
      table.column(0).text_color = TEXT_LIGHT
      table.column(1).text_color = TEXT_DARK

      # Make total row bold and larger
      table.row(2).font_style = :bold
      table.row(2).size = 12
      table.row(2).text_color = BRAND_PRIMARY

      # Make deposit row bold if present
      if has_deposit
        table.row(4).font_style = :bold
        table.row(4).text_color = BRAND_PRIMARY
      end
    end
  end

  def add_payment_terms(pdf)
    pdf.move_down 25

    pdf.font_size(11) do
      pdf.text "PAYMENT TERMS", style: :bold, color: BRAND_PRIMARY
    end
    pdf.move_down 5

    deposit_pct = ((@estimate.required_deposit / @estimate.total) * 100).round rescue 0

    terms_text = "A deposit of #{format_currency(@estimate.required_deposit)} "
    terms_text += "(#{deposit_pct}%) is required to begin work. "
    remaining = @estimate.total - @estimate.required_deposit
    terms_text += "The remaining balance of #{format_currency(remaining)} "
    terms_text += "will be due upon completion."

    pdf.font_size(9) do
      pdf.text terms_text, color: TEXT_DARK, align: :justify
    end
  end

  def add_signature_section(pdf)
    pdf.move_down 30

    pdf.font_size(11) do
      pdf.text "AUTHORIZATION", style: :bold, color: BRAND_PRIMARY
    end
    pdf.move_down 5

    # Draw accent line
    pdf.stroke_color BRAND_SECONDARY
    pdf.line_width 1
    pdf.stroke_horizontal_line 0, 120
    pdf.move_down 8

    disclaimer = "By signing below, I agree to the terms of this estimate and authorize "
    disclaimer += "#{@business.name} to proceed with the work described above."

    pdf.font_size(9) do
      pdf.text disclaimer, color: TEXT_DARK, align: :justify
    end
    pdf.move_down 15

    if @estimate.signed? && @estimate.signature_data.present?
      # Render signature image
      begin
        signature_image = decode_signature_data(@estimate.signature_data)
        if signature_image
          pdf.image signature_image, width: 200, height: 60
        else
          pdf.text "[Signature on file]", size: 10, style: :italic, color: TEXT_LIGHT
        end
      rescue => e
        Rails.logger.error "Failed to render signature: #{e.message}"
        pdf.text "[Signature on file]", size: 10, style: :italic, color: TEXT_LIGHT
      end

      pdf.move_down 5
      pdf.font_size(9) do
        pdf.text "Signed by: #{@estimate.signature_name}", color: TEXT_DARK
        pdf.text "Date: #{@estimate.signed_at.strftime('%B %d, %Y at %I:%M %p')}", color: TEXT_LIGHT
      end
    else
      # Signature line for unsigned estimates
      pdf.move_down 30
      pdf.stroke_color TEXT_LIGHT
      pdf.line_width 0.5
      pdf.stroke_horizontal_line 0, 250
      pdf.move_down 5
      pdf.font_size(9) do
        pdf.text "Customer Signature", color: TEXT_LIGHT
      end

      pdf.move_down 15
      pdf.stroke_horizontal_line 0, 150
      pdf.move_down 5
      pdf.font_size(9) do
        pdf.text "Date", color: TEXT_LIGHT
      end
    end
  end

  def add_footer(pdf)
    pdf.move_down 30

    # Footer line
    pdf.stroke_color BORDER_COLOR
    pdf.line_width 0.5
    pdf.stroke_horizontal_line 0, pdf.bounds.width
    pdf.move_down 10

    pdf.font_size(8) do
      pdf.text @business.name, align: :center, color: TEXT_DARK

      footer_info = []
      footer_info << @business.phone if @business.phone.present?
      footer_info << @business.email if @business.email.present?
      footer_info << @business.website if @business.website.present?

      pdf.text footer_info.join(' | '), align: :center, color: TEXT_LIGHT

      # License numbers if available
      if @business.respond_to?(:license_number) && @business.license_number.present?
        pdf.text "License ##{@business.license_number}", align: :center, color: TEXT_LIGHT
      end
    end

    # Page number at bottom
    pdf.number_pages "Page <page> of <total>",
      at: [pdf.bounds.right - 100, 0],
      align: :right,
      size: 8,
      color: TEXT_LIGHT
  end

  def format_currency(amount)
    "$#{'%.2f' % amount.to_f}"
  end

  def decode_signature_data(data)
    return nil unless data.present?

    # Signature data is base64 encoded PNG
    # Format: "data:image/png;base64,iVBORw0KG..."
    if data.start_with?('data:image')
      base64_data = data.split(',')[1]
      decoded = Base64.decode64(base64_data)
      StringIO.new(decoded)
    else
      decoded = Base64.decode64(data)
      StringIO.new(decoded)
    end
  rescue => e
    Rails.logger.error "Failed to decode signature: #{e.message}"
    nil
  end
end


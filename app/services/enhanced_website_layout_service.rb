class EnhancedWebsiteLayoutService
  include ActionView::Helpers::SanitizeHelper

  def self.apply!(business)
    new(business).apply!
  end

  def initialize(business)
    @business = business
  end

  def apply!
    return unless @business.present?

    ActsAsTenant.with_tenant(@business) do
      page = ensure_home_page!
      ensure_sections!(page)
      publish_page!(page)
    end
  end

  private

  attr_reader :business

  def ensure_home_page!
    business.pages.find_or_initialize_by(slug: 'home').tap do |page|
      page.title ||= 'Home'
      page.page_type ||= 'home'
      page.status ||= :draft
      page.menu_order ||= 0
      page.show_in_menu = true if page.show_in_menu.nil?
      page.content ||= nil
      page.save!
    end
  end

  def ensure_sections!(page)
    allowed_types = definitions.map { |definition| definition[:type] }
    page.page_sections.where.not(section_type: allowed_types).update_all(active: false) if page.page_sections.loaded? || page.page_sections.exists?

    definitions.each_with_index do |definition, index|
      section = page.page_sections.find_or_initialize_by(section_type: definition[:type])
      section.position = index
      section.active = true
      section.animation_type = definition[:animation]
      section.section_config = definition[:config] if definition[:config].present?
      section.custom_css_classes = definition[:css_classes] if definition[:css_classes].present?
      section.content = definition[:content] if definition[:content].present?
      section.save!
    end
  end

  def publish_page!(page)
    page.publish! unless page.published?
  rescue ActiveRecord::RecordInvalid
    # Already published or validation failed; ignore to avoid crashing layout switch.
    page.update!(status: :published, published_at: Time.current) unless page.published?
  end

  def definitions
    sections = [
      {
        type: 'hero_banner',
        animation: 'fadeIn',
        config: hero_config,
        content: hero_content
      },
      {
        type: 'text',
        animation: 'slideUp',
        css_classes: 'enhanced-story-block',
        content: story_content
      }
    ]

    sections << service_section_definition if include_service_section?
    sections << product_section_definition if include_product_section?

    sections << {
      type: 'testimonial',
      animation: 'slideUp',
      config: { 'source' => 'google_reviews', 'limit' => 4 },
      content: testimonial_content
    }

    sections << {
      type: 'newsletter_signup',
      animation: 'fadeIn',
      content: newsletter_content
    }

    sections << {
      type: 'social_media',
      animation: 'fadeIn',
      content: social_content
    }

    sections
  end

  def hero_config
    {
      'theme' => 'dark_showcase'
    }
  end

  def hero_content
    {
      'title' => business.name,
      'subtitle' => hero_subtitle,
      'button_text' => 'Book Now',
      'button_link' => booking_link,
      'secondary_button_text' => 'Contact',
      'secondary_button_link' => contact_link
    }
  end

  def hero_subtitle
    return business.description if business.description.present?

    "Professional #{business.industry&.to_s&.humanize || 'services'} trusted by customers across #{business.city}, #{business.state}."
  end

  def story_content
    {
      'title' => 'Why Customers Choose Us',
      'content' => <<~HTML.squish
        <div class="enhanced-story-content">
          <p>#{ERB::Util.h(story_intro)}</p>
          <p class="mt-4">#{ERB::Util.h(story_secondary)}</p>
        </div>
      HTML
    }
  end

  def story_intro
    return business.description if business.description.present?

    "#{business.name} delivers thoughtful, detail-driven service for every client interaction."
  end

  def story_secondary
    "We're based in #{service_areas_sentence}. From the first hello to the final handshake, our team keeps standards high."
  end

  def service_areas_sentence
    [business.city, business.state].compact.join(', ').presence || 'your area'
  end

  def highlighted_services_copy
    "Explore our most-requested offerings below. Each service is crafted to deliver the results our clients rave about."
  end

  def include_service_section?
    business.show_services_section? && business.has_visible_services?
  end

  def include_product_section?
    business.show_products_section? && business.has_visible_products?
  end

  def service_section_definition
    {
      type: 'service_list',
      animation: 'slideUp',
      config: { 'layout' => 'grid', 'columns' => 3, 'limit' => 6 },
      content: {
        'title' => 'Signature Services',
        'description' => highlighted_services_copy
      }
    }
  end

  def product_section_definition
    {
      type: 'product_list',
      animation: 'slideUp',
      config: { 'layout' => 'grid', 'columns' => 3, 'limit' => 6 },
      content: {
        'title' => 'Featured Products',
        'description' => "Premium products we trust and use."
      }
    }
  end

  def testimonial_content
    {
      'title' => 'Real Talk With Real Customers',
      'fallback_quote' => "We rely on #{business.name} because they treat every project like it matters.",
      'fallback_author' => business.name
    }
  end

  def newsletter_content
    {
      'title' => 'Stay In The Loop',
      'subtitle' => 'Drop your email and we will reach out with seasonal promotions, tips, and openings.',
      'button_text' => 'Notify Me',
      'placeholder' => 'you@example.com'
    }
  end

  def social_content
    {
      'title' => 'Let’s Stay Connected',
      'description' => "Follow #{business.name} online and keep up with the latest work, promotions, and behind-the-scenes updates."
    }
  end

  def booking_link
    routes.tenant_calendar_path
  rescue
    '#book'
  end

  def contact_link
    routes.tenant_contact_page_path
  rescue
    '#contact'
  end

  def routes
    Rails.application.routes.url_helpers
  end
end


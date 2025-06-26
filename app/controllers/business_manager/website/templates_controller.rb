class BusinessManager::Website::TemplatesController < BusinessManager::Website::BaseController
  before_action :set_template, only: [:show, :apply, :preview]
  
  def index
    @templates = WebsiteTemplateService.available_templates_for_business(current_business)
    @industry_templates = @templates.industry_specific.for_industry(current_business.industry)
    @universal_templates = @templates.universal
    @current_template = current_business.template_applied
  end
  
  def show
    @preview_data = WebsiteTemplateService.preview_template(@template.id, current_business.id)
    @can_apply = @template.can_be_used_by?(current_business)
  end
  
  def apply
    unless @template.can_be_used_by?(current_business)
      respond_to do |format|
        format.html { redirect_to business_manager_website_templates_path, alert: 'Template not available for your business tier or industry' }
        format.json { render json: { status: 'error', message: 'Template not available' } }
      end
      return
    end
    
    if WebsiteTemplateService.apply_template(current_business, @template.id, current_user)
      respond_to do |format|
        format.html { 
          redirect_to business_manager_website_pages_path, 
                      notice: "Template '#{@template.name}' applied successfully! Your pages have been created and are ready for customization."
        }
        format.json { render json: { status: 'success', redirect_url: business_manager_website_pages_path } }
      end
    else
      respond_to do |format|
        format.html { redirect_to business_manager_website_template_path(@template), alert: 'Failed to apply template' }
        format.json { render json: { status: 'error', message: 'Failed to apply template' } }
      end
    end
  end
  
  def preview
    @preview_data = WebsiteTemplateService.preview_template(@template.id, current_business.id)
    @theme_css = @preview_data[:theme_css]
    @sample_pages = generate_sample_pages
    
    # Debug logging
    Rails.logger.info "Template ID: #{@template.id}"
    Rails.logger.info "Template Name: #{@template.name}"
    Rails.logger.info "Theme CSS: #{@theme_css}"
    Rails.logger.info "Preview Data: #{@preview_data}"
    
    respond_to do |format|
      format.html { render layout: 'website_preview' }
      format.json { 
        render json: { 
          template: @template,
          preview_data: @preview_data,
          theme_css: @theme_css,
          sample_html: render_sample_html
        } 
      }
    end
  end
  
  def search
    @search_query = params[:q]
    @industry_filter = params[:industry]
    @tier_filter = params[:tier]
    
    @templates = WebsiteTemplate.active.includes(:business)
    
    if @search_query.present?
      @templates = @templates.where(
        "name ILIKE ? OR description ILIKE ?", 
        "%#{@search_query}%", "%#{@search_query}%"
      )
    end
    
    if @industry_filter.present? && @industry_filter != 'all'
      @templates = @templates.where(industry: [@industry_filter, 'universal'])
    end
    
    if @tier_filter.present?
      @templates = @templates.available_for_tier(@tier_filter)
    else
      @templates = @templates.available_for_tier(current_business.tier)
    end
    
    @templates = @templates.order(:template_type, :name).limit(20)
    
    respond_to do |format|
      format.html { render :index }
      format.json { render json: @templates.map { |t| template_json(t) } }
    end
  end
  
  def filter_by_industry
    industry = params[:industry]
    
    if industry == 'all'
      @templates = WebsiteTemplateService.available_templates_for_business(current_business)
    else
      @templates = WebsiteTemplate.active
                                  .available_for_tier(current_business.tier)
                                  .for_industry(industry)
    end
    
    respond_to do |format|
      format.json { render json: @templates.map { |t| template_json(t) } }
    end
  end
  
  def compare
    template_ids = params[:template_ids] || []
    @templates = WebsiteTemplate.where(id: template_ids).limit(3)
    
    @comparison_data = @templates.map do |template|
      {
        template: template,
        preview_data: WebsiteTemplateService.preview_template(template.id, current_business.id),
        features: extract_template_features(template)
      }
    end
    
    respond_to do |format|
      format.html
      format.json { render json: @comparison_data }
    end
  end
  
  private
  
  def set_template
    @template = WebsiteTemplate.find(params[:id])
  end
  
  def generate_sample_pages
    @template.structure['pages'].map do |page_data|
      {
        title: page_data['title'],
        slug: page_data['slug'],
        sections: page_data['sections'].map do |section|
          {
            type: section['type'],
            content: sample_content_for_section(section['type'])
          }
        end
      }
    end
  end
  
  def sample_content_for_section(section_type)
    case section_type
    when 'hero_banner'
      "Welcome to #{current_business.name} - Your trusted #{current_business.industry.humanize} service"
    when 'text'
      "#{current_business.description} We pride ourselves on quality service and customer satisfaction."
    when 'service_list'
      current_business.services.active.limit(3).pluck(:name).join(', ')
    when 'product_list'
      current_business.products.active.limit(3).pluck(:name).join(', ')
    when 'testimonial'
      "\"Excellent service and professional staff. Highly recommended!\" - Satisfied Customer"
    when 'contact_form'
      "Ready to get started? Contact us today for a consultation."
    when 'feature_showcase'
      "Why Choose #{current_business.name}: Expert Team • Quality Service • 24/7 Support • Proven Results"
    when 'call_to_action'
      "Ready to transform your business? Contact #{current_business.name} today for a free consultation!"
    when 'stats_counter'
      "500+ Happy Clients • 10+ Years Experience • 99% Success Rate • 24/7 Support"
    when 'portfolio_gallery'
      "View our recent projects and success stories from #{current_business.industry.humanize} clients"
    when 'social_links'
      "Connect with #{current_business.name} on social media - Facebook • Twitter • LinkedIn • Instagram"
    when 'map_location'
      "Visit our office at #{current_business.address || '123 Business Street, City, State 12345'}"
    when 'team_showcase'
      "Meet the #{current_business.name} team - John Smith CEO • Jane Doe Director • Mike Johnson Manager"
    when 'company_values'
      "Our core values: Integrity • Excellence • Innovation • Customer Focus"
    when 'pricing_table'
      "Our service packages: Basic Plan $99 • Premium Plan $199 • Enterprise Plan $399"
    when 'case_study_list'
      "Success stories: Tech Startup Growth • Retail Transformation • Healthcare Innovation"
    when 'business_hours'
      "Hours: Mon-Fri 9AM-6PM • Saturday 10AM-4PM • Sunday Closed"
    else
      "Sample content for #{section_type.humanize} section"
    end
  end
  
  def render_sample_html
    render_to_string(
      partial: 'templates/preview_sample',
      locals: { 
        template: @template,
        preview_data: @preview_data,
        sample_pages: @sample_pages
      }
    )
  end

  # Helper method to render sample sections for preview
  helper_method :render_sample_section
  
  def render_sample_section(section, business)
    case section[:type]
    when 'hero_banner'
      %{
        <div class="hero-content text-center">
          <h1>Welcome to #{ERB::Util.html_escape(business.name)}</h1>
          <p>#{ERB::Util.html_escape(business.description || 'Professional services you can trust')}</p>
          <a href="#contact" class="cta-button">Get Started Today</a>
        </div>
      }.html_safe
    when 'text'
      %{
        <div>
          <h2>About #{ERB::Util.html_escape(business.name)}</h2>
          <p>#{ERB::Util.html_escape(business.description || 'We provide exceptional services to help you achieve your goals. Our experienced team is committed to delivering quality results that exceed your expectations.')}</p>
        </div>
      }.html_safe
    when 'service_list'
      services_html = ['Consultation', 'Implementation', 'Support'].map do |service|
        %{
          <div class="service-item">
            <h3 class="font-semibold text-lg mb-2">#{ERB::Util.html_escape(service)}</h3>
            <p>Professional #{ERB::Util.html_escape(service.downcase)} services tailored to your needs.</p>
          </div>
        }
      end.join
      
      %{
        <div>
          <h2>Our Services</h2>
          <div class="service-grid">
            #{services_html}
          </div>
        </div>
      }.html_safe
    when 'product_list'
      products_html = ['Premium Product', 'Standard Product', 'Basic Product'].map do |product|
        %{
          <div class="product-item">
            <h3 class="font-semibold text-lg mb-2">#{ERB::Util.html_escape(product)}</h3>
            <p>High-quality #{ERB::Util.html_escape(product.downcase)} designed to meet your needs.</p>
            <div class="price font-bold text-primary">Starting at $99</div>
          </div>
        }
      end.join
      
      %{
        <div>
          <h2>Our Products</h2>
          <div class="product-grid">
            #{products_html}
          </div>
        </div>
      }.html_safe
    when 'testimonial'
      %{
        <div class="text-center">
          <h2>What Our Clients Say</h2>
          <blockquote>"Exceptional service and outstanding results. Highly recommended!"</blockquote>
          <p class="font-semibold">— Satisfied Customer</p>
        </div>
      }.html_safe
    when 'contact_form'
      %{
        <div class="text-center">
          <h2>Get In Touch</h2>
          <p>Ready to get started? Contact #{ERB::Util.html_escape(business.name)} today for a consultation.</p>
          <a href="#" class="cta-button">Contact Us Now</a>
        </div>
      }.html_safe
    when 'feature_showcase'
      features = ['Expert Team', 'Quality Service', '24/7 Support', 'Proven Results']
      features_html = features.map do |feature|
        %{<div class="feature-item"><h3>#{ERB::Util.html_escape(feature)}</h3><p>Excellence in #{ERB::Util.html_escape(feature.downcase)}</p></div>}
      end.join
      
      %{
        <div class="text-center">
          <h2>Why Choose #{ERB::Util.html_escape(business.name)}</h2>
          <div class="features-grid">#{features_html}</div>
        </div>
      }.html_safe
    when 'call_to_action'
      %{
        <div class="text-center bg-accent text-white p-8">
          <h2>Ready to Transform Your Business?</h2>
          <p>Contact #{ERB::Util.html_escape(business.name)} today for a free consultation!</p>
          <a href="#" class="cta-button cta-button-white">Get Started Now</a>
        </div>
      }.html_safe
    when 'stats_counter'
      stats = [
        { number: '500+', label: 'Happy Clients' },
        { number: '10+', label: 'Years Experience' },
        { number: '99%', label: 'Success Rate' }
      ]
      stats_html = stats.map do |stat|
        %{<div class="stat-item"><span class="stat-number">#{ERB::Util.html_escape(stat[:number])}</span><span class="stat-label">#{ERB::Util.html_escape(stat[:label])}</span></div>}
      end.join
      
      %{
        <div class="text-center">
          <h2>Our Success</h2>
          <div class="stats-grid">#{stats_html}</div>
        </div>
      }.html_safe
    when 'portfolio_gallery'
      projects = ['Modern Office Design', 'Retail Space Transform', 'Restaurant Renovation', 'Corporate Headquarters']
      projects_html = projects.map do |project|
        %{<div class="portfolio-item"><h3>#{ERB::Util.html_escape(project)}</h3><p>Professional #{ERB::Util.html_escape(business.industry.humanize)} project</p></div>}
      end.join
      
      %{
        <div>
          <h2>Our Portfolio</h2>
          <div class="portfolio-grid">#{projects_html}</div>
        </div>
      }.html_safe
    when 'team_showcase'
      team_members = ['John Smith - CEO', 'Jane Doe - Director', 'Mike Johnson - Manager']
      team_html = team_members.map do |member|
        %{<div class="team-member"><h3>#{ERB::Util.html_escape(member)}</h3><p>Expert professional with years of experience</p></div>}
      end.join
      
      %{
        <div class="text-center">
          <h2>Meet Our Team</h2>
          <div class="team-grid">#{team_html}</div>
        </div>
      }.html_safe
    when 'company_values'
      values = ['Integrity', 'Excellence', 'Innovation', 'Customer Focus']
      values_html = values.map do |value|
        %{<div class="value-item"><h3>#{ERB::Util.html_escape(value)}</h3><p>We are committed to #{ERB::Util.html_escape(value.downcase)} in everything we do</p></div>}
      end.join
      
      %{
        <div class="text-center">
          <h2>Our Values</h2>
          <div class="values-grid">#{values_html}</div>
        </div>
      }.html_safe
    when 'pricing_table'
      plans = [
        { name: 'Basic', price: '$99', features: ['Feature 1', 'Feature 2', 'Email Support'] },
        { name: 'Premium', price: '$199', features: ['Everything in Basic', 'Feature 3', 'Priority Support'] },
        { name: 'Enterprise', price: '$399', features: ['Everything in Premium', 'Custom Solutions', 'Dedicated Manager'] }
      ]
      plans_html = plans.map do |plan|
        features_list = plan[:features].map { |f| "<li>#{ERB::Util.html_escape(f)}</li>" }.join
        %{
          <div class="pricing-plan">
            <h3>#{ERB::Util.html_escape(plan[:name])}</h3>
            <div class="price">#{ERB::Util.html_escape(plan[:price])}</div>
            <ul>#{features_list}</ul>
            <a href="#" class="cta-button">Choose Plan</a>
          </div>
        }
      end.join
      
      %{
        <div class="text-center">
          <h2>Our Pricing</h2>
          <div class="pricing-grid">#{plans_html}</div>
        </div>
      }.html_safe
    when 'case_study_list'
      studies = ['Tech Startup Growth', 'Retail Transformation', 'Healthcare Innovation']
      studies_html = studies.map do |study|
        %{<div class="case-study"><h3>#{ERB::Util.html_escape(study)}</h3><p>Successful #{ERB::Util.html_escape(business.industry.humanize)} transformation case study</p></div>}
      end.join
      
      %{
        <div>
          <h2>Case Studies</h2>
          <div class="case-studies-grid">#{studies_html}</div>
        </div>
      }.html_safe
    when 'social_links'
      %{
        <div class="text-center">
          <h2>Connect With Us</h2>
          <div class="social-links">
            <a href="#">Facebook</a>
            <a href="#">Twitter</a>
            <a href="#">LinkedIn</a>
            <a href="#">Instagram</a>
          </div>
        </div>
      }.html_safe
    when 'map_location'
      %{
        <div class="text-center">
          <h2>Visit Our Office</h2>
          <p>#{ERB::Util.html_escape(business.address || '123 Business Street, City, State 12345')}</p>
          <div class="map-placeholder">Map Location</div>
        </div>
      }.html_safe
    when 'business_hours'
      %{
        <div class="text-center">
          <h2>Business Hours</h2>
          <div class="hours-list">
            <div>Monday - Friday: 9:00 AM - 6:00 PM</div>
            <div>Saturday: 10:00 AM - 4:00 PM</div>
            <div>Sunday: Closed</div>
          </div>
        </div>
      }.html_safe
    else
      %{
        <div>
          <h2>#{ERB::Util.html_escape(section[:type].to_s.humanize)}</h2>
          <p>#{ERB::Util.html_escape(section[:content] || 'Sample content for this section type.')}</p>
        </div>
      }.html_safe
    end
  end
  
  def template_json(template)
    {
      id: template.id,
      name: template.name,
      description: template.description,
      industry: template.industry,
      template_type: template.template_type,
      requires_premium: template.requires_premium?,
      preview_image_url: template.preview_image_url_or_default,
      can_use: template.can_be_used_by?(current_business)
    }
  end
  
  def extract_template_features(template)
    features = []
    
    template.structure['pages'].each do |page|
      page['sections']&.each do |section|
        features << section['type'].humanize
      end
    end
    
    features.uniq
  end
end 
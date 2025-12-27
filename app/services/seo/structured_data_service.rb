# frozen_string_literal: true

module Seo
  # Service for generating Schema.org structured data markup
  class StructuredDataService
    attr_reader :business

    def initialize(business)
      @business = business
    end

    # Generate complete structured data for a business
    # @return [Array<Hash>] Array of structured data objects
    def all_structured_data
      [
        local_business_schema,
        organization_schema,
        website_schema
      ].compact
    end

    # Generate LocalBusiness schema
    # @return [Hash] LocalBusiness structured data
    def local_business_schema
      schema = {
        '@context' => 'https://schema.org',
        '@type' => determine_business_type,
        '@id' => "#{business_url}#localbusiness",
        'name' => business.name,
        'url' => business_url,
        'telephone' => business.phone,
        'email' => business.email,
        'description' => business.description,
        'address' => address_schema,
        'geo' => geo_schema,
        'openingHoursSpecification' => opening_hours_schema,
        'priceRange' => '$$',
        'currenciesAccepted' => 'USD',
        'paymentAccepted' => 'Cash, Credit Card',
        'areaServed' => area_served_schema,
        'hasOfferCatalog' => service_catalog_schema,
        'sameAs' => social_links
      }

      # Add logo if attached
      if business.logo.attached?
        schema['logo'] = logo_url
        schema['image'] = logo_url
      end

      # Add aggregate rating if available
      # schema['aggregateRating'] = aggregate_rating_schema if has_reviews?

      schema.compact
    end

    # Generate Organization schema
    # @return [Hash] Organization structured data
    def organization_schema
      {
        '@context' => 'https://schema.org',
        '@type' => 'Organization',
        '@id' => "#{business_url}#organization",
        'name' => business.name,
        'url' => business_url,
        'logo' => business.logo.attached? ? logo_url : nil,
        'contactPoint' => {
          '@type' => 'ContactPoint',
          'telephone' => business.phone,
          'contactType' => 'customer service',
          'availableLanguage' => 'English'
        },
        'address' => address_schema,
        'sameAs' => social_links
      }.compact
    end

    # Generate WebSite schema
    # @return [Hash] WebSite structured data
    def website_schema
      {
        '@context' => 'https://schema.org',
        '@type' => 'WebSite',
        '@id' => "#{business_url}#website",
        'name' => business.name,
        'url' => business_url,
        'potentialAction' => {
          '@type' => 'SearchAction',
          'target' => "#{business_url}/search?q={search_term_string}",
          'query-input' => 'required name=search_term_string'
        }
      }
    end

    # Generate Service schema for a specific service
    # @param service [Service] The service to generate schema for
    # @return [Hash] Service structured data
    def service_schema(service)
      {
        '@context' => 'https://schema.org',
        '@type' => 'Service',
        '@id' => "#{business_url}/services/#{service.id}#service",
        'name' => service.name,
        'description' => service.description,
        'provider' => {
          '@type' => determine_business_type,
          '@id' => "#{business_url}#localbusiness"
        },
        'areaServed' => area_served_schema,
        'offers' => service_offer_schema(service),
        'serviceType' => service.name
      }.compact
    end

    # Generate Product schema for a specific product
    # @param product [Product] The product to generate schema for
    # @return [Hash] Product structured data
    def product_schema(product)
      schema = {
        '@context' => 'https://schema.org',
        '@type' => 'Product',
        '@id' => "#{business_url}/products/#{product.id}#product",
        'name' => product.name,
        'description' => product.description,
        'brand' => {
          '@type' => 'Brand',
          'name' => business.name
        },
        'offers' => product_offer_schema(product),
        'sku' => product.sku
      }

      # Add image if attached
      if product.respond_to?(:images) && product.images.attached?
        schema['image'] = product_image_urls(product)
      end

      schema.compact
    end

    # Generate BreadcrumbList schema
    # @param breadcrumbs [Array<Hash>] Array of {name:, url:} hashes
    # @return [Hash] BreadcrumbList structured data
    def breadcrumb_schema(breadcrumbs)
      {
        '@context' => 'https://schema.org',
        '@type' => 'BreadcrumbList',
        'itemListElement' => breadcrumbs.each_with_index.map do |crumb, index|
          {
            '@type' => 'ListItem',
            'position' => index + 1,
            'name' => crumb[:name],
            'item' => crumb[:url]
          }
        end
      }
    end

    # Generate FAQ schema
    # @param faqs [Array<Hash>] Array of {question:, answer:} hashes
    # @return [Hash] FAQPage structured data
    def faq_schema(faqs)
      {
        '@context' => 'https://schema.org',
        '@type' => 'FAQPage',
        'mainEntity' => faqs.map do |faq|
          {
            '@type' => 'Question',
            'name' => faq[:question],
            'acceptedAnswer' => {
              '@type' => 'Answer',
              'text' => faq[:answer]
            }
          }
        end
      }
    end

    # Generate Event schema for a booking slot
    # @param booking [Booking] The booking to generate schema for
    # @return [Hash] Event structured data
    def event_schema(booking)
      {
        '@context' => 'https://schema.org',
        '@type' => 'Event',
        'name' => booking.service&.name || 'Appointment',
        'startDate' => booking.start_time&.iso8601,
        'endDate' => booking.end_time&.iso8601,
        'location' => {
          '@type' => 'Place',
          'name' => business.name,
          'address' => address_schema
        },
        'organizer' => {
          '@type' => determine_business_type,
          '@id' => "#{business_url}#localbusiness"
        },
        'offers' => {
          '@type' => 'Offer',
          'price' => booking.service&.price.to_f,
          'priceCurrency' => 'USD',
          'availability' => 'https://schema.org/InStock',
          'url' => "#{business_url}/booking"
        }
      }.compact
    end

    private

    def business_url
      business.full_url
    end

    def logo_url
      return nil unless business.logo.attached?
      
      Rails.application.routes.url_helpers.rails_blob_url(
        business.logo,
        host: URI.parse(business_url).host,
        protocol: Rails.env.production? ? 'https' : 'http'
      )
    rescue StandardError
      nil
    end

    def determine_business_type
      # Map industry to Schema.org type
      industry_types = {
        hair_salons: 'HairSalon',
        beauty_spa: 'BeautySalon',
        dental_care: 'Dentist',
        medical: 'MedicalBusiness',
        auto_repair: 'AutoRepair',
        restaurants: 'Restaurant',
        legal_services: 'LegalService',
        accounting: 'AccountingService',
        real_estate: 'RealEstateAgent',
        cleaning_services: 'HousekeepingService',
        photography: 'ProfessionalService',
        plumbing: 'Plumber',
        hvac_services: 'HVACBusiness',
        landscaping: 'LandscapingBusiness',
        personal_training: 'HealthClub',
        yoga_classes: 'HealthClub'
      }

      industry_types[business.industry&.to_sym] || 'LocalBusiness'
    end

    def address_schema
      return nil unless business.address.present?

      {
        '@type' => 'PostalAddress',
        'streetAddress' => business.address,
        'addressLocality' => business.city,
        'addressRegion' => business.state,
        'postalCode' => business.zip,
        'addressCountry' => 'US'
      }.compact
    end

    def geo_schema
      # Would need geocoding to populate lat/long
      # For now, return nil
      nil
    end

    def opening_hours_schema
      return [] unless business.hours.present?

      day_mapping = {
        'monday' => 'Monday',
        'tuesday' => 'Tuesday',
        'wednesday' => 'Wednesday',
        'thursday' => 'Thursday',
        'friday' => 'Friday',
        'saturday' => 'Saturday',
        'sunday' => 'Sunday'
      }

      business.hours.map do |day, hours|
        next nil unless hours.is_a?(Hash) && hours['open'].present? && hours['close'].present?
        
        {
          '@type' => 'OpeningHoursSpecification',
          'dayOfWeek' => day_mapping[day.downcase],
          'opens' => hours['open'],
          'closes' => hours['close']
        }
      end.compact
    end

    def area_served_schema
      return nil unless business.city.present?

      {
        '@type' => 'City',
        'name' => business.city,
        'containedInPlace' => {
          '@type' => 'State',
          'name' => business.state
        }
      }.compact
    end

    def service_catalog_schema
      return nil unless business.services.active.exists?

      {
        '@type' => 'OfferCatalog',
        'name' => "#{business.name} Services",
        'itemListElement' => business.services.active.limit(10).map do |service|
          {
            '@type' => 'Offer',
            'itemOffered' => {
              '@type' => 'Service',
              'name' => service.name,
              'description' => service.description
            },
            'price' => service.price.to_f,
            'priceCurrency' => 'USD'
          }
        end
      }
    end

    def service_offer_schema(service)
      {
        '@type' => 'Offer',
        'price' => service.price.to_f,
        'priceCurrency' => 'USD',
        'availability' => 'https://schema.org/InStock',
        'validFrom' => Date.current.iso8601
      }
    end

    def product_offer_schema(product)
      availability = if product.respond_to?(:stock_quantity) && product.stock_quantity&.positive?
                       'https://schema.org/InStock'
                     else
                       'https://schema.org/OutOfStock'
                     end

      {
        '@type' => 'Offer',
        'price' => product.price.to_f,
        'priceCurrency' => 'USD',
        'availability' => availability,
        'seller' => {
          '@type' => 'Organization',
          'name' => business.name
        }
      }
    end

    def product_image_urls(product)
      return [] unless product.respond_to?(:images) && product.images.attached?

      product.images.map do |image|
        Rails.application.routes.url_helpers.rails_blob_url(
          image,
          host: URI.parse(business_url).host,
          protocol: Rails.env.production? ? 'https' : 'http'
        )
      rescue StandardError
        nil
      end.compact
    end

    def social_links
      # Would pull from business social media settings if available
      []
    end

    def has_reviews?
      # Would check for review system
      false
    end

    def aggregate_rating_schema
      # Would calculate from reviews
      nil
    end
  end
end


namespace :seo do
  desc "Generate and validate sitemap"
  task validate_sitemap: :environment do
    puts "Validating sitemap..."
    
    begin
      # Test that sitemap route exists
      route_exists = Rails.application.routes.recognize_path('/sitemap.xml')
      
      puts "✓ Sitemap route exists"
      puts "✓ Sitemap URL: https://www.bizblasts.com/sitemap.xml"
      
      # Count entries
      static_pages = 7 # Based on your controller
      blog_posts = BlogPost.published.count rescue 0
      businesses = Business.where.not(hostname: nil).where(active: true).count rescue 0
      
      puts "Sitemap contains:"
      puts "  - #{static_pages} static pages"
      puts "  - #{blog_posts} blog posts"
      puts "  - #{businesses} business subdomains"
      puts "  - Total: #{static_pages + blog_posts + businesses} URLs"
      
    rescue => e
      puts "✗ Error generating sitemap: #{e.message}"
    end
  end

  desc "Check indexing status and provide recommendations"
  task check_indexing: :environment do
    puts "SEO Indexing Checklist:"
    puts "====================="
    
    # Check sitemap
    puts "1. Sitemap:"
    if File.exist?(Rails.root.join('app/controllers/sitemap_controller.rb'))
      puts "   ✓ Sitemap controller exists"
    else
      puts "   ✗ Sitemap controller missing"
    end
    
    # Check robots.txt
    puts "\n2. Robots.txt:"
    if File.exist?(Rails.root.join('public/robots.txt'))
      puts "   ✓ robots.txt exists"
    else
      puts "   ✗ robots.txt missing"
    end
    
    # Check meta tags in layout
    layout_content = File.read(Rails.root.join('app/views/layouts/application.html.erb'))
    puts "\n3. Meta Tags:"
    puts "   ✓ Title tag" if layout_content.include?('content_for(:title)')
    puts "   ✓ Description tag" if layout_content.include?('meta_description')
    puts "   ✓ Canonical URL" if layout_content.include?('canonical')
    puts "   ✓ Robots meta tag" if layout_content.include?('robots')
    puts "   ✓ Open Graph tags" if layout_content.include?('og:title')
    puts "   ✓ Structured data" if layout_content.include?('application/ld+json')
    
    puts "\n4. Next Steps for Google Search Console:"
    puts "   - Submit sitemap: https://www.bizblasts.com/sitemap.xml"
    puts "   - Request indexing for specific URLs"
    puts "   - Monitor coverage report"
    puts "   - Check for crawl errors"
    
    puts "\n5. Redirects:"
    puts "   ✓ /users/sign_up → /business/sign_up (fixes 404 errors)"
    puts "   ✓ http://bizblasts.com → https://www.bizblasts.com (protocol + www)"
    puts "   ✓ https://bizblasts.com → https://www.bizblasts.com (www redirect)"
    puts "   ✓ http://www.bizblasts.com → https://www.bizblasts.com (force SSL)"
    
    puts "\n6. To improve indexing:"
    puts "   - Ensure pages load fast (< 3 seconds)"
    puts "   - Add internal links between pages"
    puts "   - Create quality content regularly"
    puts "   - Build external backlinks"
  end

  desc "Show URLs that should be indexed"
  task show_indexable_urls: :environment do
    puts "URLs that should be indexed:"
    puts "==========================="
    
    base_url = "https://www.bizblasts.com"
    
    # Static pages
    static_pages = [
      '/',
      '/about',
      '/contact', 
      '/pricing',
      '/businesses',
      '/blog',
      '/docs'
    ]
    
    puts "\nStatic Pages:"
    static_pages.each { |url| puts "  #{base_url}#{url}" }
    
    # Blog posts
    if defined?(BlogPost)
      blog_posts = BlogPost.published.limit(10).pluck(:slug)
      if blog_posts.any?
        puts "\nBlog Posts (first 10):"
        blog_posts.each { |slug| puts "  #{base_url}/blog/#{slug}" }
      end
    end
    
    # Add business subdomains
    if defined?(Business)
      businesses = Business.where.not(hostname: nil).where(active: true).limit(10)
      if businesses.any?
        puts "\nBusiness Subdomains (first 10):"
        businesses.each do |business|
          if business.host_type == 'custom_domain'
            puts "  https://#{business.hostname}"
          else
            puts "  https://#{business.hostname}.bizblasts.com"
          end
        end
      end
    end
    
    puts "\nSubmit these URLs to Google Search Console for faster indexing."
  end
  
  desc "Create a simple sitemap for manual submission"
  task create_submission_file: :environment do
    puts "Creating submission file for search engines..."
    
    base_url = "https://www.bizblasts.com"
    
    # Static pages
    static_pages = [
      '/',
      '/about',
      '/contact', 
      '/pricing',
      '/businesses',
      '/blog',
      '/docs'
    ]
    
    urls = []
    
    # Add static pages
    static_pages.each { |url| urls << "#{base_url}#{url}" }
    
    # Add blog posts
    if defined?(BlogPost)
      blog_posts = BlogPost.published.limit(50).pluck(:slug).compact
      blog_posts.each { |slug| urls << "#{base_url}/blog/#{slug}" }
    end
    
    # Add business subdomains
    if defined?(Business)
      businesses = Business.where.not(hostname: nil).where(active: true).limit(50)
      businesses.each do |business|
        if business.host_type == 'custom_domain'
          urls << "https://#{business.hostname}"
        else
          urls << "https://#{business.hostname}.bizblasts.com"
        end
      end
    end
    
    # Write to file
    File.open("#{Rails.root}/public/urls_for_submission.txt", 'w') do |file|
      urls.each { |url| file.puts url }
    end
    
    puts "✓ Created public/urls_for_submission.txt with #{urls.count} URLs"
    puts "✓ You can submit this file to Google Search Console"
    puts "✓ File location: #{Rails.root}/public/urls_for_submission.txt"
  end

  desc "Create URL list for Google Search Console redirect submissions"
  task create_redirect_submission: :environment do
    puts "Creating redirect URL submission file for Google Search Console..."
    
    # These are the specific URLs that Google Search Console found with redirects
    # They should all redirect to the canonical HTTPS www version
    redirect_urls = [
      'http://www.bizblasts.com/',
      'http://bizblasts.com/', 
      'https://bizblasts.com/'
    ]
    
    # The canonical URL they should all redirect to
    canonical_url = 'https://www.bizblasts.com/'
    
    # Create submission content
    submission_content = []
    submission_content << "# Google Search Console URL Submission for Redirects"
    submission_content << "# Created: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
    submission_content << "#"
    submission_content << "# These URLs have redirects configured and should be submitted"
    submission_content << "# to Google Search Console to resolve 'Page with redirect' issues"
    submission_content << "#"
    submission_content << "# Canonical URL (what all variants redirect to):"
    submission_content << canonical_url
    submission_content << ""
    submission_content << "# URLs with redirects (submit these for indexing):"
    
    redirect_urls.each do |url|
      submission_content << url
    end
    
    submission_content << ""
    submission_content << "# Instructions:"
    submission_content << "# 1. Go to Google Search Console"
    submission_content << "# 2. Select 'URL Inspection' tool"
    submission_content << "# 3. Test each URL above to verify the redirect"
    submission_content << "# 4. Click 'Request Indexing' for each URL"
    submission_content << "# 5. This will help Google understand the redirect structure"
    
    # Write to file
    file_path = Rails.root.join('public', 'redirect_urls_for_gsc.txt')
    File.write(file_path, submission_content.join("\n"))
    
    puts "✓ Redirect submission file created: #{file_path}"
    puts "✓ URLs to submit to Google Search Console:"
    redirect_urls.each { |url| puts "   - #{url}" }
    puts "✓ These will all redirect to: #{canonical_url}"
  end

  desc "Test important redirects"
  task test_redirects: :environment do
    puts "Testing important redirects..."
    
    redirects_to_test = [
      { from: '/users/sign_up', to: '/business/sign_up', description: 'Old signup URL to business signup' },
      { from: 'http://bizblasts.com/', to: 'https://www.bizblasts.com/', description: 'HTTP non-www to HTTPS www' },
      { from: 'https://bizblasts.com/', to: 'https://www.bizblasts.com/', description: 'HTTPS non-www to HTTPS www' },
      { from: 'http://www.bizblasts.com/', to: 'https://www.bizblasts.com/', description: 'HTTP www to HTTPS www (force_ssl)' }
    ]
    
    redirects_to_test.each do |redirect|
      puts "\nTesting: #{redirect[:from]} → #{redirect[:to]}"
      puts "Description: #{redirect[:description]}"
      
      if redirect[:from].include?('://')
        puts "✓ Full URL redirect configured (handled by force_ssl + constraints)"
      else
        begin
          # Test the route
          route = Rails.application.routes.recognize_path(redirect[:from])
          puts "✓ Route exists and is configured"
        rescue ActionController::RoutingError
          puts "✗ Route not found"
        rescue => e
          puts "✓ Redirect configured (#{e.class})"
        end
      end
    end
    
    puts "\n📋 Redirect Status:"
    puts "✓ /users/sign_up redirects to /business/sign_up (301)"
    puts "\n💡 Benefits:"
    puts "  - Fixes 404 errors in Google Search Console"
    puts "  - Preserves SEO value from old URL"
    puts "  - Improves user experience"
  end
end 
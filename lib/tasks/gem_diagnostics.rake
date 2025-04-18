# lib/tasks/gem_diagnostics.rake
namespace :diagnostics do
  desc "Check which key gems are actively loaded and used in the application"
  task check_loaded_gems: :environment do
    # Helper method to check if a gem is loaded and report its version
    def check_gem(name, constant_path = nil)
      begin
        if Gem.loaded_specs[name]
          version = Gem.loaded_specs[name].version
          loaded = "✓ LOADED (v#{version})"
          
          # Check if constant is available (indicates the gem code is accessible)
          if constant_path
            constant = constant_path.split('::').inject(Object) do |mod, class_name|
              mod.const_get(class_name) if mod.const_defined?(class_name)
            rescue
              nil
            end
            
            if constant
              constant_status = "✓ CONSTANT AVAILABLE"
            else
              constant_status = "✗ CONSTANT NOT AVAILABLE"
            end
          else
            constant_status = "-"
          end
        else
          loaded = "✗ NOT LOADED"
          constant_status = "-"
        end
      rescue => e
        loaded = "✗ ERROR (#{e.message})"
        constant_status = "-"
      end
      
      puts "#{name.ljust(20)} | #{loaded.ljust(20)} | #{constant_status}"
    end
    
    # Check asset pipeline configuration
    def check_asset_pipeline
      pipeline = Rails.application.config.assets.respond_to?(:compiler) ? "Propshaft" : "Sprockets"
      puts "\nAsset Pipeline: #{pipeline}"
    end
    
    # Check JavaScript handling
    def check_js_processor
      if defined?(Webpacker)
        js = "Webpacker"
      elsif defined?(Jsbundling)
        js = "JSBundling"
      elsif defined?(Importmap)
        js = "ImportMap"
      else
        js = "Unknown"
      end
      puts "JavaScript Processor: #{js}"
    end
    
    # Print header
    puts "\n=== GEM DIAGNOSTICS ==="
    puts "#{'Gem'.ljust(20)} | #{'Load Status'.ljust(20)} | Constant Check"
    puts "-" * 70
    
    # Check core gems
    check_gem('turbo-rails', 'Turbo')
    check_gem('propshaft', 'Propshaft')
    check_gem('sprockets-rails', 'Sprockets')
    check_gem('rails-ujs', 'Rails::UJS')
    check_gem('importmap-rails', 'Importmap')
    check_gem('webpacker', 'Webpacker')
    check_gem('jsbundling-rails', 'Jsbundling')
    check_gem('activeadmin', 'ActiveAdmin')
    check_gem('devise', 'Devise')
    check_gem('pundit', 'Pundit')
    check_gem('acts_as_tenant', 'ActsAsTenant')
    
    # Check configuration
    check_asset_pipeline
    check_js_processor
    
    # Check for specific ActiveAdmin integrations
    puts "\n=== ACTIVEADMIN INTEGRATION ==="
    
    if defined?(ActiveAdmin)
      puts "ActiveAdmin Version: #{ActiveAdmin::VERSION}"
      
      # Check if Rails UJS is properly initialized
      puts "\nChecking for UJS in ActiveAdmin JavaScript:"
      begin
        aa_js_path = ActiveAdmin::Engine.root.join('app/assets/javascripts/active_admin/base.js').to_s
        if File.exist?(aa_js_path)
          content = File.read(aa_js_path)
          if content.include?('rails-ujs') || content.include?('jquery_ujs')
            puts "✓ UJS found in ActiveAdmin JavaScript"
          else
            puts "✗ UJS not found in ActiveAdmin JavaScript"
          end
        else
          puts "? Could not find ActiveAdmin base JS file"
        end
      rescue => e
        puts "✗ Error checking ActiveAdmin JS: #{e.message}"
      end
    else
      puts "ActiveAdmin is not defined - check failed"
    end
    
    puts "\n=== ROUTES ANALYSIS ==="
    # Check if DELETE routes are properly set up
    puts "Sample DELETE route analysis for service_templates:"
    delete_routes = Rails.application.routes.routes.select do |route|
      route.verb == "DELETE" && route.path.spec.to_s.include?("service_templates")
    end
    
    if delete_routes.any?
      delete_routes.each do |route|
        puts "✓ #{route.verb} #{route.path.spec} => #{route.defaults[:controller]}##{route.defaults[:action]}"
      end
    else
      puts "✗ No DELETE routes found for service_templates"
    end
  end
end

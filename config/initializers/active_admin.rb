# frozen_string_literal: true
if ENV.fetch("LOW_USAGE_MODE", "false") != "true"
  require 'activeadmin'

  ActiveAdmin.setup do |config|
  # == Site Title
  #
  # Set the title that is displayed on the main layout
  # for each of the active admin pages.
  #
  config.site_title = "BizBlasts Admin"

  # Set the link url for the title. For example, to take
  # users to your main site. Defaults to no link.
  #
  config.site_title_link = "/"

  # This is the recommended way to add JavaScript to ActiveAdmin in Rails 8
  config.authentication_method = :authenticate_admin_user!

  # ActiveAdmin-specific JavaScript lives in app/assets/javascripts.
  # Files like delete_fix.js are bundled via Sprockets (see active_admin.js),
  # which avoids runtime file reads and keeps static analysis happy.

  # Add timezone handling JavaScript
  # This is a static script defined in this initializer file
  timezone_js = <<~JAVASCRIPT
    // Client-side timezone detection and conversion for ActiveAdmin
    document.addEventListener('DOMContentLoaded', function() {
      // Get client timezone
      const clientTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      
      // Find all timestamp elements and convert them to local time
      const convertTimestamps = function() {
        // Convert elements with data-timestamp attribute
        document.querySelectorAll('[data-timestamp]').forEach(function(element) {
          const isoTimestamp = element.getAttribute('data-timestamp');
          if (isoTimestamp) {
            const date = new Date(isoTimestamp);
            const localText = date.toLocaleString('en-US', {
              timeZone: clientTimezone,
              year: 'numeric',
              month: 'long',
              day: 'numeric',
              hour: 'numeric',
              minute: '2-digit',
              hour12: true,
              timeZoneName: 'short'
            });
            element.textContent = localText;
          }
        });
        
        // Also handle any existing UTC timestamps that don't have data attributes
        document.querySelectorAll('*').forEach(function(element) {
          const text = element.textContent;
          
          // Match the specific format from the screenshot: "August 11, 2025 04:03"
          const dateTimePattern = /(January|February|March|April|May|June|July|August|September|October|November|December) (\d{1,2}), (\d{4}) (\d{2}):(\d{2})/g;
          
          if (text.match(dateTimePattern) && !element.hasAttribute('data-timestamp')) {
            const newText = text.replace(dateTimePattern, function(match, month, day, year, hour, minute) {
              // Assume this is UTC time
              const utcDate = new Date(`${year}-${String(new Date(Date.parse(month + " 1, 2000")).getMonth() + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}T${hour}:${minute}:00Z`);
              return utcDate.toLocaleString('en-US', {
                timeZone: clientTimezone,
                year: 'numeric',
                month: 'long',
                day: 'numeric',
                hour: 'numeric',
                minute: '2-digit',
                hour12: true,
                timeZoneName: 'short'
              });
            });
            
            if (newText !== text && element.children.length === 0) {
              element.textContent = newText;
            }
          }
        });
      };
      
      // Convert timestamps when page loads
      setTimeout(convertTimestamps, 100);
      
      // Convert timestamps when content changes (for AJAX updates)
      const observer = new MutationObserver(function(mutations) {
        let shouldConvert = false;
        mutations.forEach(function(mutation) {
          if (mutation.addedNodes.length > 0) {
            shouldConvert = true;
          }
        });
        if (shouldConvert) {
          setTimeout(convertTimestamps, 200);
        }
      });
      
      observer.observe(document.body, {
        childList: true,
        subtree: true
      });
    });
  JAVASCRIPT

  # Inject inline JavaScript that cannot easily live in a separate asset
  inline_scripts = []
  inline_scripts << "<script>#{timezone_js}</script>" if timezone_js.present?

  config.head = inline_scripts.join.html_safe if inline_scripts.any?

  # Add custom CSS for better login styling
  custom_css = <<~CSS
    <style>
      /* Universal approach - target all text elements on login page */
      body.logged_out {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      }
      
      /* Force white text on ALL elements within the login form */
      body.logged_out #login,
      body.logged_out #login *,
      body.logged_out #login h1,
      body.logged_out #login h2,
      body.logged_out #login h3,
      body.logged_out #login h4,
      body.logged_out #login h5,
      body.logged_out #login h6,
      body.logged_out #login .panel,
      body.logged_out #login .panel *,
      body.logged_out #login .panel h1,
      body.logged_out #login .panel h2,
      body.logged_out #login .panel h3,
      body.logged_out #login div,
      body.logged_out #login div * {
        color: #ffffff !important;
        text-shadow: none !important;
      }
      
      /* Specific styling for the container */
      body.logged_out #login .panel {
        background: white !important;
        border-radius: 12px !important;
        padding: 40px !important;
        max-width: 400px !important;
        margin: 0 auto !important;
        box-shadow: 0 10px 30px rgba(0, 0, 0, 0.15) !important;
      }
      
      /* Force the title area to have gradient background */
      body.logged_out #login .panel > *:first-child,
      body.logged_out #login > *:first-child {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%) !important;
        color: #ffffff !important;
        padding: 15px 20px !important;
        margin: -40px -40px 30px -40px !important;
        border-radius: 12px 12px 0 0 !important;
        text-align: center !important;
        font-weight: 600 !important;
      }
      
      /* Flash messages */
      body.logged_out .flash_notice,
      body.logged_out .flash_alert,
      body.logged_out .flash,
      body.logged_out #flash_notice,
      body.logged_out #flash_alert {
        color: #ffffff !important;
        background: rgba(255, 255, 255, 0.15) !important;
        border: 1px solid rgba(255, 255, 255, 0.3) !important;
        border-radius: 8px !important;
        padding: 12px 20px !important;
        margin: 20px auto !important;
        max-width: 400px !important;
        text-align: center !important;
        font-weight: 500 !important;
        box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1) !important;
      }
      
      /* Ensure inputs and labels are readable */
      body.logged_out #login input,
      body.logged_out #login textarea,
      body.logged_out #login select {
        color: #333 !important;
        background: white !important;
      }
      
      body.logged_out #login label {
        color: #4a5568 !important;
      }
    </style>
  CSS

  # Append custom CSS to existing head content
  # Note: custom_css is a static heredoc defined in this initializer file
  # It's safe to mark as html_safe since it's controlled content from the application code
  if custom_css.present?
    config.head = [config.head, custom_css].compact.join.html_safe
  end

  # Register ActiveAdmin JavaScript (Sprockets-based)
  # This uses the traditional asset pipeline for full compatibility
  config.register_javascript 'active_admin.js'

  # Set an optional image to be displayed for the header
  # instead of a string (overrides :site_title)
  #
  # Note: Aim for an image that's 21px high so it fits in the header.
  #
  # config.site_title_image = "logo.png"

  # == Load Paths
  #
  # By default Active Admin files go inside app/admin/.
  # You can change this directory.
  #
  # eg:
  #   config.load_paths = [File.join(Rails.root, 'app', 'ui')]
  #
  # Or, you can also load more directories.
  # Useful when setting namespaces with users that are not your main AdminUser entity.
  #
  # eg:
  #   config.load_paths = [
  #     File.join(Rails.root, 'app', 'admin'),
  #     File.join(Rails.root, 'app', 'cashier')
  #   ]

  # == Default Namespace
  #
  # Set the default namespace each administration resource
  # will be added to.
  #
  # eg:
  #   config.default_namespace = :hello_world
  #
  # This will create resources in the HelloWorld module and
  # will namespace routes to /hello_world/*
  #
  # To set no namespace by default, use:
  #   config.default_namespace = false
  #
  # Default:
  # config.default_namespace = :admin
  #
  # You can customize the settings for each namespace by using
  # a namespace block. For example, to change the site title
  # for a specific namespace:
  #
  #   config.namespace :admin do |admin|
  #     admin.site_title = "Custom Admin Title"
  #   end
  #
  # This will ONLY change the title for the admin section. Other
  # namespaces will continue to use the main "site_title" configuration.

  # == User Authentication
  #
  # Active Admin will automatically call an authentication
  # method in a before filter of all controller actions to
  # ensure that there is a currently logged in admin user.
  #
  # This setting changes the method which Active Admin calls
  # within the application controller.
  config.authentication_method = :authenticate_admin_user!

  # == User Authorization
  #
  # Active Admin will automatically call an authorization
  # method in a before filter of all controller actions to
  # ensure that there is a user with proper rights. You can use
  # CanCanAdapter or make your own. Please refer to documentation.
  config.authorization_adapter = ActiveAdmin::PunditAdapter
  config.pundit_policy_namespace = :admin

  # In case you prefer Pundit over other solutions you can here pass
  # the name of default policy class. This policy will be used in every
  # case when Pundit is unable to find suitable policy.
  config.pundit_default_policy = "Admin::DefaultPolicy"

  # You can customize your CanCan Ability class name here.
  # config.cancan_ability_class = "Ability"

  # You can specify a method to be called on unauthorized access.
  # This is necessary in order to prevent a redirect loop which happens
  # because, by default, user gets redirected to Dashboard. If user
  # doesn't have access to Dashboard, he'll end up in a redirect loop.
  # Method provided here should be defined in application_controller.rb.
  # config.on_unauthorized_access = :access_denied

  # == Current User
  #
  # Active Admin will associate actions with the current
  # user performing them.
  #
  # This setting changes the method which Active Admin calls
  # (within the application controller) to return the currently logged in user.
  config.current_user_method = :current_admin_user

  # == Logging Out
  #
  # Active Admin displays a logout link on each screen. These
  # settings configure the location and method used for the link.
  #
  # This setting changes the path where the link points to. If it's
  # a string, the strings is used as the path. If it's a Symbol, we
  # will call the method to return the path.
  #
  # Default:
  config.logout_link_path = :destroy_admin_user_session_path

  # This setting changes the http method used when rendering the
  # link. For example :get, :delete, :put, etc..
  #
  # Default:
  # config.logout_link_method = :get

  # == Root
  #
  # Set the action to call for the root path. You can set different
  # roots for each namespace.
  #
  # Default:
  # config.root_to = 'dashboard#index'

  # == Admin Comments
  #
  # This allows your users to comment on any resource registered with Active Admin.
  #
  # You can completely disable comments:
  config.comments = false
  #
  # You can change the name under which comments are registered:
  # config.comments_registration_name = 'AdminComment'
  #
  # You can change the order for the comments and you can change the column
  # to be used for ordering:
  # config.comments_order = 'created_at ASC'
  #
  # You can disable the menu item for the comments index page:
  # config.comments_menu = false
  #
  # You can customize the comment menu:
  # config.comments_menu = { parent: 'Admin', priority: 1 }

  # == Batch Actions
  #
  # Enable and disable Batch Actions
  #
  config.batch_actions = true

  # == Controller Filters
  #
  # You can add before, after and around filters to all of your
  # Active Admin resources and pages from here.
  #
  # Tenant handling for multi-tenancy - unscope tenancy for admin users
  config.before_action do
    ActsAsTenant.current_tenant = nil if request.path.include?('/admin')
  end

  # == Attribute Filters
  #
  # You can exclude possibly sensitive model attributes from being displayed,
  # added to forms, or exported by default by ActiveAdmin
  #
  config.filter_attributes = [:encrypted_password, :password, :password_confirmation]

  # == Localize Date/Time Format
  #
  # Set the localize format to display dates and times.
  # To understand how to localize your app with I18n, read more at
  # https://guides.rubyonrails.org/i18n.html
  #
  # You can run `bin/rails runner 'puts I18n.t("date.formats")'` to see the
  # available formats in your application.
  #
  config.localize_format = :long

  # == Setting a Favicon
  #
  config.favicon = 'icon.svg'

  # == Meta Tags
  #
  # Add additional meta tags to the head element of active admin pages.
  #
  # Add tags to all pages logged in users see:
  #   config.meta_tags = { author: 'My Business' }

  # By default, sign up/sign in/recover password pages are excluded
  # from showing up in search engine results by adding a robots meta
  # tag. You can reset the hash of meta tags included in logged out
  # pages:
  #   config.meta_tags_for_logged_out_pages = {}

  # == Removing Breadcrumbs
  #
  # Breadcrumbs are enabled by default. You can customize them for individual
  # resources or you can disable them globally from here.
  #
  # config.breadcrumb = false

  # == Create Another Checkbox
  #
  # Create another checkbox is disabled by default. You can customize it for individual
  # resources or you can enable them globally from here.
  #
  # config.create_another = true

  # == Register Stylesheets & Javascripts
  #
  # We recommend using the built in Active Admin layout and loading
  # up your own stylesheets / javascripts to customize the look
  # and feel.
  #
  # To load a stylesheet:
  #   config.register_stylesheet 'my_stylesheet.css'
  #
  # You can provide an options hash for more control, which is passed along to stylesheet_link_tag():
  #   config.register_stylesheet 'my_print_stylesheet.css', media: :print
  #
  # To load a javascript file:
  #   config.register_javascript 'my_javascript.js'

  # == CSV options
  #
  # Set the CSV builder separator
  # config.csv_options = { col_sep: ';' }
  #
  # Force the use of quotes
  # config.csv_options = { force_quotes: true }

  # == Menu System
  #
  # You can add a navigation menu to be used in your application, or configure a provided menu
  #
  # To change the default utility navigation to show a link to your website & a logout btn
  #
  #   config.namespace :admin do |admin|
  #     admin.build_menu :utility_navigation do |menu|
  #       menu.add label: "My Great Website", url: "http://www.mygreatwebsite.com", html_options: { target: :blank }
  #       admin.add_logout_button_to_menu menu
  #     end
  #   end
  #
  # If you wanted to add a static menu item to the default menu provided:
  #
  config.namespace :admin do |admin|
    admin.build_menu :default do |menu|
      menu.add label: "Dashboard", url: "/admin/dashboard", priority: 1
      menu.add label: "Websites", url: "/admin/websites", priority: 2
    end
  end

  # == Download Links
  #
  # You can disable download links on resource listing pages,
  # or customize the formats shown per namespace/globally
  #
  # To disable/customize for the :admin namespace:
  #
  #   config.namespace :admin do |admin|
  #
  #     # Disable the links entirely
  #     admin.download_links = false
  #
  #     # Only show XML & PDF options
  #     admin.download_links = [:xml, :pdf]
  #
  #     # Enable/disable the links based on block
  #     #
  #     # admin.download_links = proc { |admin| user.admin? }
  #
  #   end

  # == Pagination
  #
  # Pagination is enabled by default for all resources.
  # You can control the default per page count for all resources here.
  #
  # config.default_per_page = 30
  #
  # You can control the max per page count too.
  #
  # config.max_per_page = 10_000

  # == Filters
  #
  # By default the index screen includes a "Filters" sidebar on the right
  # hand side with a filter for each attribute of the registered model.
  # You can enable or disable them for all resources here.
  #
  # config.filters = true
  #
  # By default the filters include associations in a select, which means
  # that every record will be loaded for each association (up
  # to the value of config.maximum_association_filter_arity).
  # You can enabled or disable the inclusion
  # of those filters by default here.
  #
  # config.include_default_association_filters = true

  # config.maximum_association_filter_arity = 256 # default value of :unlimited will change to 256 in a future version
  # config.filter_columns_for_large_association = [
  #    :display_name,
  #    :full_name,
  #    :name,
  #    :username,
  #    :login,
  #    :title,
  #    :email,
  #  ]
  # config.filter_method_for_large_association = '_starts_with'

  # == Head
  #
  # You can add your own content to the site head like analytics. Make sure
  # you only pass content you trust.
  #
  # config.head = ''.html_safe

  # == Footer
  #
  # By default, the footer shows the current Active Admin version. You can
  # override the content of the footer here.
  #
  config.footer = 'BizBlasts Admin'

  # == Sorting
  #
  # By default ActiveAdmin::OrderClause is used for sorting logic
  # You can inherit it with own class and inject it for all resources
  #
  # config.order_clause = MyOrderClause

  end
end

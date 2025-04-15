require Rails.root.join('lib/subdomain_redirect')

Rails.application.config.middleware.use SubdomainRedirect 
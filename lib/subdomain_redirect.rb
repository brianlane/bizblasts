class SubdomainRedirect
  def initialize(app)
    @app = app
  end

  def call(env)
    req = Rack::Request.new(env)
    host = req.host

    # If host matches something like "test.localhost", redirect to "test.lvh.me"
    if host =~ /(.+)\.localhost$/i
      subdomain = $1
      new_host = "#{subdomain}.lvh.me"
      port_part = (![80, 443].include?(req.port) && req.port) ? ":#{req.port}" : ""
      location = "#{req.scheme}://#{new_host}#{port_part}#{req.fullpath}"
      return [301, { 'Location' => location, 'Content-Type' => 'text/html' }, ["Redirecting to #{location}"]]
    end

    @app.call(env)
  end
end 
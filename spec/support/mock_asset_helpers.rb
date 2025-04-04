# frozen_string_literal: true

# Include this module in your specs to mock the asset pipeline helpers
module MockAssetHelpers
  # Mock asset path helper
  def asset_path(source, options = {})
    "/assets/#{source}"
  end
  
  # Mock stylesheet tag helper
  def stylesheet_link_tag(*sources)
    options = sources.extract_options!
    sources.map { |source| %(<link rel="stylesheet" href="/assets/#{source}.css">) }.join("\n").html_safe
  end
  
  # Mock javascript tag helper
  def javascript_include_tag(*sources)
    options = sources.extract_options!
    sources.map { |source| %(<script src="/assets/#{source}.js"></script>) }.join("\n").html_safe
  end
end 
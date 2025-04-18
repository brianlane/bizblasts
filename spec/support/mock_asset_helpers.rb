# frozen_string_literal: true

# Include this module in your specs to mock the asset pipeline helpers
module MockAssetHelpers
  def asset_path(source, options = {})
    "/assets/#{source}"
  end
  
  def stylesheet_link_tag(*sources)
    options = sources.extract_options!.stringify_keys
    sources.map { |source| 
      %(<link rel="stylesheet" media="#{options['media'] || 'screen'}" href="/assets/#{source}#{'.css' unless source.to_s.end_with?('.css')}">) 
    }.join("\n").html_safe
  end
  
  def javascript_include_tag(*sources)
    options = sources.extract_options!.stringify_keys
    sources.map { |source| 
      %(<script src="/assets/#{source}#{'.js' unless source.to_s.end_with?('.js')}"#{' defer="defer"' if options['defer']}></script>)
    }.join("\n").html_safe
  end

  # Mock importmap helper
  def javascript_importmap_tags(entry_point = 'application')
    %(<script type="importmap">{"imports":{}}</script><script type="module">import "#{entry_point}"</script>).html_safe
  end
end
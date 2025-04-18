module BusinessManager::ServicesHelper
  def format_service_duration(minutes)
    hours = minutes / 60
    remaining_minutes = minutes % 60
    
    if hours > 0
      "#{hours}h #{remaining_minutes}m"
    else
      "#{minutes}m"
    end
  end

  def service_status_tag(service)
    if service.active?
      tag.span('Active', class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-green-100 text-green-800')
    else
      tag.span('Inactive', class: 'px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-red-100 text-red-800')
    end
  end
end

module AssociationCacheHelpers
  # Clear association cache for a specific association on a model instance
  # This helps prevent test pollution when associations are modified
  def clear_association_cache(model, association_name)
    model.association(association_name).reset if model.association(association_name).loaded?
  end

  # Clear all association caches for a model instance
  def clear_all_association_caches(model)
    model.class.reflect_on_all_associations.each do |association|
      clear_association_cache(model, association.name)
    end
  end

  # Reload a model and clear its association caches
  def reload_with_cache_clearing(model)
    model.reload
    clear_all_association_caches(model)
    model
  end
end

RSpec.configure do |config|
  config.include AssociationCacheHelpers
end 
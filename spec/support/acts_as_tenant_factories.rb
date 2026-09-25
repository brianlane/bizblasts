# frozen_string_literal: true

# acts_as_tenant 2.0 rejects records whose business is not the current tenant,
# and belongs_to associations that point at another business. Factories used to
# rely on 1.x silently rewriting the tenant. Align them before save.
module TenantFactoryAligner
  module_function

  def align!(record, overrides)
    return unless record.class.respond_to?(:scoped_by_tenant?)
    return unless record.respond_to?(:business_id)

    overrides = Array(overrides).map(&:to_sym)
    tenant = ActsAsTenant.current_tenant

    unless overrides.include?(:business)
      if tenant
        record.business = tenant
      elsif (from_association = business_from_override(record, overrides))
        record.business = from_association
      end
    end

    return if record.business_id.nil?

    record.class.reflect_on_all_associations(:belongs_to).each do |assoc|
      next if assoc.name == :business || assoc.polymorphic?
      next if overrides.include?(assoc.name)
      next unless assoc.klass.respond_to?(:scoped_by_tenant?)

      associated = record.public_send(assoc.name)
      next unless associated&.respond_to?(:business_id)
      next if associated.business_id == record.business_id

      associated.business = record.business
      if associated.persisted? && associated.will_save_change_to_business_id?
        associated.update_columns(business_id: record.business_id)
      end
    end
  end

  def business_from_override(record, overrides)
    overrides.each do |name|
      assoc = record.class.reflect_on_association(name)
      next unless assoc&.macro == :belongs_to
      next if assoc.polymorphic?
      next unless assoc.klass.respond_to?(:scoped_by_tenant?)

      associated = record.public_send(name)
      return associated.business if associated.respond_to?(:business) && associated.business
    end
    nil
  end
end

module TenantFactoryStrategy
  def result(evaluation)
    evaluation.notify(:before_build, nil)

    evaluation.object.tap do |instance|
      evaluation.notify(:after_build, instance)
      overrides = evaluation.instance_variable_get(:@evaluator).__override_names__
      TenantFactoryAligner.align!(instance, overrides)
      next unless is_a?(FactoryBot::Strategy::Create)

      evaluation.notify(:before_create, instance)
      evaluation.create(instance)
      evaluation.notify(:after_create, instance)
    end
  end
end

FactoryBot::Strategy::Create.prepend(TenantFactoryStrategy)
FactoryBot::Strategy::Build.prepend(TenantFactoryStrategy)

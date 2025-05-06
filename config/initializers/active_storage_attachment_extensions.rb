# config/initializers/active_storage_attachment_extensions.rb
# Extend ActiveStorage::Attached::Many to add an `ordered` helper
Rails.application.config.to_prepare do
  ActiveStorage::Attached::Many.class_eval do
    def ordered
      # Order by the `position` column on active_storage_attachments
      attachments.order(:position)
    end
  end
end 
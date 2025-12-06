class AllowNullDocumentableOnClientDocuments < ActiveRecord::Migration[8.1]
  def change
    change_column_null :client_documents, :documentable_id, true
    change_column_null :client_documents, :documentable_type, true
  end
end

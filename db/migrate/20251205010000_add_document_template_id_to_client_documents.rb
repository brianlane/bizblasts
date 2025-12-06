class AddDocumentTemplateIdToClientDocuments < ActiveRecord::Migration[8.1]
  def change
    add_reference :client_documents, :document_template, foreign_key: true
  end
end

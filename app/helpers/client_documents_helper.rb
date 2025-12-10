module ClientDocumentsHelper
  def document_status_badge(status)
    case status.to_s
    when 'pending_signature'
      'bg-amber-100 text-amber-800'
    when 'pending_payment'
      'bg-indigo-100 text-indigo-800'
    when 'completed'
      'bg-green-100 text-green-800'
    when 'void'
      'bg-gray-100 text-gray-700'
    else
      'bg-slate-100 text-slate-700'
    end
  end

  def document_type_label(document)
    case document.document_type.to_s
    when 'waiver'
      'Waiver'
    when 'rental'
      'Rental Agreement'
    when 'estimate'
      'Estimate'
    else
      document.document_type.to_s.titleize
    end
  end
end


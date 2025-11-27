class EstimateVersion < ApplicationRecord
  belongs_to :estimate

  validates :version_number, presence: true,
    numericality: { only_integer: true, greater_than: 0 }
  validates :snapshot, presence: true

  scope :ordered, -> { order(version_number: :asc) }
  scope :recent, -> { order(version_number: :desc) }

  def estimate_data
    snapshot['estimate']
  end

  def items_data
    snapshot['items'] || []
  end

  def created_timestamp
    Time.parse(snapshot['created_at']) rescue created_at
  end

  # Returns human-readable summary of changes
  def changes_summary
    change_notes.presence || "Version #{version_number}"
  end
end


class PageSection < ApplicationRecord
  belongs_to :page

  validates :section_type, presence: true
  validates :content, presence: true
  validates :position, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  enum :section_type, {
    header: 0,
    text: 1,
    image: 2,
    gallery: 3,
    contact_form: 4,
    service_list: 5,
    testimonial: 6,
    cta: 7,
    custom: 8
  }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position) }
end

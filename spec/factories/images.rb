FactoryBot.define do
  factory :image, class: 'ActiveStorage::Attachment' do
    # Allow passing `imageable` to associate the attachment to a custom record
    transient do
      imageable { nil }
    end

    after(:build) do |attachment, evaluator|
      # Assign to the provided imageable record if given
      attachment.record = evaluator.imageable if evaluator.imageable.present?
    end

    # Default association if no custom imageable is provided
    association :record, factory: :product
    name { 'images' }
    blob do
      ActiveStorage::Blob.create_and_upload!(
        io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test_image.jpg')),
        filename: 'test_image.jpg',
        content_type: 'image/jpeg'
      )
    end
  end
end 
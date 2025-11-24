# frozen_string_literal: true

FactoryBot.define do
  factory :gallery_photo do
    association :business
    sequence(:title) { |n| "Gallery Photo #{n}" }
    description { Faker::Lorem.sentence }
    photo_source { :gallery }
    # Position will be set automatically by the model

    # By default, attach a test image for gallery photos
    after(:build) do |photo|
      if photo.photo_source_gallery? && !photo.image.attached?
        photo.image.attach(
          io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test_image.jpg')),
          filename: 'test_image.jpg',
          content_type: 'image/jpeg'
        )
      end
    end

    trait :from_service do
      photo_source { :service }

      after(:build) do |photo|
        # Remove the automatically attached image for service photos
        photo.image.purge if photo.image.attached?

        # Create a service with an image if not already set
        unless photo.source.present?
          service = create(:service, business: photo.business)
          service.images.attach(
            io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test_image.jpg')),
            filename: 'service-image.jpg',
            content_type: 'image/jpeg'
          )
          photo.source = service
          photo.source_attachment_id = service.images.first.id
        end
      end
    end

    trait :from_product do
      photo_source { :product }

      after(:build) do |photo|
        # Remove the automatically attached image for product photos
        photo.image.purge if photo.image.attached?

        # Create a product with an image if not already set
        unless photo.source.present?
          product = create(:product, business: photo.business)
          product.images.attach(
            io: File.open(Rails.root.join('spec', 'fixtures', 'files', 'test_image.jpg')),
            filename: 'product-image.jpg',
            content_type: 'image/jpeg'
          )
          photo.source = product
          photo.source_attachment_id = product.images.first.id
        end
      end
    end
  end
end

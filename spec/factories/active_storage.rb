# frozen_string_literal: true

require 'digest/md5'

FactoryBot.define do
  factory :active_storage_blob, class: 'ActiveStorage::Blob' do
    sequence(:key) { |n| "test-key-#{SecureRandom.hex(8)}-#{n}" }
    filename { 'test_image.jpg' }
    content_type { 'image/jpeg' }
    metadata { { identified: true, analyzed: true } }
    byte_size { 1024 }
    checksum { Digest::MD5.base64digest('test') }

    after(:build) do |blob|
      blob.service_name ||= ActiveStorage::Blob.services.keys.first || 'test'
    end
  end

  factory :active_storage_attachment, class: 'ActiveStorage::Attachment' do
    name { 'images' }
    association :blob, factory: :active_storage_blob
    association :record, factory: :service
  end
end

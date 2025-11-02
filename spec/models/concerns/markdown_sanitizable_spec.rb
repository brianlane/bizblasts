# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MarkdownSanitizable, type: :model do
  # Create a test model class that includes the concern
  let(:test_class) do
    Class.new do
      include ActiveModel::Model
      include ActiveModel::Dirty
      include ActiveModel::Validations::Callbacks
      include MarkdownSanitizable

      attr_accessor :content, :description
      define_attribute_methods :content, :description

      markdown_fields :content

      def self.name
        'TestArticle'
      end

      def content=(value)
        content_will_change!
        @content = value
      end

      def description=(value)
        description_will_change!
        @description = value
      end
    end
  end

  let(:instance) { test_class.new }

  describe 'server-side sanitization' do
    it 'strips script tags' do
      instance.content = '<script>alert("XSS")</script>Hello'
      instance.valid?
      
      expect(instance.content).not_to include('<script>')
      expect(instance.content).to eq('Hello')
    end

    it 'strips event handlers' do
      instance.content = '<img src=x onerror="alert(1)">'
      instance.valid?

      # Sanitize::Config::RELAXED allows img tags but strips dangerous attributes
      expect(instance.content).not_to include('onerror')
      expect(instance.content).to include('<img')
      expect(instance.content).to eq('<img src="x">')
    end

    it 'strips iframe tags' do
      instance.content = '<iframe src="evil.com"></iframe>Hello'
      instance.valid?
      
      expect(instance.content).not_to include('<iframe')
      expect(instance.content).to eq('Hello')
    end

    it 'allows safe HTML tags' do
      instance.content = '<p><strong>Bold</strong> and <em>italic</em></p>'
      instance.valid?
      
      expect(instance.content).to include('<strong>')
      expect(instance.content).to include('<em>')
      expect(instance.content).to include('<p>')
    end

    it 'allows safe links' do
      instance.content = '<a href="https://example.com">Link</a>'
      instance.valid?
      
      expect(instance.content).to include('<a href="https://example.com">')
      expect(instance.content).to include('Link')
    end

    it 'strips dangerous link protocols' do
      instance.content = '<a href="javascript:alert(1)">Click</a>'
      instance.valid?
      
      expect(instance.content).not_to include('javascript:')
      expect(instance.content).to include('Click')
    end

    it 'only sanitizes declared markdown fields' do
      instance.content = '<script>alert(1)</script>'
      instance.description = '<script>alert(2)</script>'
      instance.valid?
      
      # content is declared as markdown field, should be sanitized
      expect(instance.content).not_to include('<script>')
      
      # description is NOT declared, should not be sanitized
      expect(instance.description).to include('<script>')
    end

    it 'only sanitizes changed fields' do
      instance.content = 'Safe content'
      instance.changes_applied

      # Content hasn't changed since changes_applied, so sanitization shouldn't modify it
      original_content = instance.content
      instance.valid?

      # Content should remain unchanged because the field wasn't marked as changed
      expect(instance.content).to eq(original_content)
    end

    it 'handles nil values gracefully' do
      instance.content = nil
      expect { instance.valid? }.not_to raise_error
      expect(instance.content).to be_nil
    end

    it 'handles empty strings gracefully' do
      instance.content = ''
      instance.valid?
      expect(instance.content).to eq('')
    end
  end

  describe 'class methods' do
    it 'declares markdown fields' do
      expect(test_class._markdown_fields).to include('content')
    end

    it 'accepts multiple markdown fields' do
      multi_field_class = Class.new do
        include ActiveModel::Model
        include ActiveModel::Validations::Callbacks
        include MarkdownSanitizable

        attr_accessor :content, :description, :notes

        markdown_fields :content, :description, :notes
      end

      expect(multi_field_class._markdown_fields).to eq(['content', 'description', 'notes'])
    end
  end
end

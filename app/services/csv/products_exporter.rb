# frozen_string_literal: true

module Csv
  class ProductsExporter < BaseExporter
    protected

    def headers
      [
        'ID', 'Name', 'Description', 'Price', 'Stock Quantity',
        'Active', 'Product Type', 'Featured', 'Tips Enabled', 'Created At'
      ]
    end

    def row_for(product)
      [
        product.id,
        product.name,
        product.description,
        format_currency(product.price),
        product.stock_quantity,
        format_boolean(product.active),
        product.product_type,
        format_boolean(product.featured),
        format_boolean(product.tips_enabled),
        format_datetime(product.created_at)
      ]
    end

    def sample_row
      [
        '', 'Product Name', 'Product description', '29.99', '100',
        'true', 'standard', 'false', 'false', ''
      ]
    end

    def default_records
      business.products.order(:name)
    end

    def export_name
      'products'
    end
  end
end

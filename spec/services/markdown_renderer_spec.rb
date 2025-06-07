require 'rails_helper'

RSpec.describe MarkdownRenderer do
  describe '.render' do
    context 'with bullet points' do
      it 'converts bullet point characters to markdown lists' do
        content = <<~TEXT
          Here are some benefits:
          
          • First benefit here
          • Second benefit here  
          • Third benefit here
          
          This is another paragraph.
        TEXT
        
        result = MarkdownRenderer.render(content)
        
        expect(result).to include('<ul class="markdown-list markdown-ul">')
        expect(result).to include('First benefit here')
        expect(result).to include('Second benefit here')
        expect(result).to include('Third benefit here')
      end
      
      it 'handles mixed bullet point characters' do
        content = <<~TEXT
          • First with bullet
          · Second with middle dot
          - Third with dash
        TEXT
        
        result = MarkdownRenderer.render(content)
        
        expect(result).to include('<ul class="markdown-list markdown-ul">')
        expect(result).to include('First with bullet')
        expect(result).to include('Second with middle dot')
        expect(result).to include('Third with dash')
      end
    end
    
    context 'with regular markdown lists' do
      it 'handles unordered lists correctly' do
        content = <<~TEXT
          - First item
          - Second item
          - Third item
        TEXT
        
        result = MarkdownRenderer.render(content)
        
        expect(result).to include('<ul class="markdown-list markdown-ul">')
        expect(result).to include('First item')
      end
      
      it 'handles ordered lists correctly' do
        content = <<~TEXT
          1. First item
          2. Second item
          3. Third item
        TEXT
        
        result = MarkdownRenderer.render(content)
        
        expect(result).to include('<ol class="markdown-list markdown-ol">')
        expect(result).to include('First item')
      end
    end
    
    context 'with nested lists' do
      it 'handles nested bullet points' do
        content = <<~TEXT
          • Top level item
            • Nested item
            • Another nested item
          • Another top level item
        TEXT
        
        result = MarkdownRenderer.render(content)
        
        expect(result).to include('<ul class="markdown-list markdown-ul">')
        expect(result).to include('<li class="markdown-list-item">Top level item')
      end
    end
    
    context 'with bold text in lists' do
      it 'preserves formatting within list items' do
        content = <<~TEXT
          • **Bold text** in list item
          • *Italic text* in list item
          • Regular text in list item
        TEXT
        
        result = MarkdownRenderer.render(content)
        
        expect(result).to include('<strong>Bold text</strong>')
        expect(result).to include('<em>Italic text</em>')
        expect(result).to include('<li class="markdown-list-item">')
      end
    end
    
    context 'with sections and headers' do
      it 'handles sections with headers and lists' do
        content = <<~TEXT
          # Main Header
          
          Here's a paragraph before the list.
          
          • First benefit
          • Second benefit
          
          ## Another Section
          
          More content here.
        TEXT
        
        result = MarkdownRenderer.render(content)
        
        expect(result).to include('<h1')
        expect(result).to include('<h2')
        expect(result).to include('<ul class="markdown-list markdown-ul">')
        expect(result).to include('Here&#39;s a paragraph before the list.')
      end
    end
  end
end 
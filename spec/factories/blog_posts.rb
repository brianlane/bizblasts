FactoryBot.define do
  factory :blog_post do
    title { "Sample Blog Post" }
    excerpt { "This is a sample excerpt for the blog post." }
    content { "# Sample Content\n\nThis is the sample content for the blog post." }
    category { "tutorial" }
    author_name { "Test Author" }
    author_email { "author@example.com" }
    published { true }
    published_at { Time.current }
    
    trait :unpublished do
      published { false }
      published_at { nil }
    end
    
    trait :with_markdown_content do
      content { "# Markdown Title\n\n**Bold text** and *italic text*.\n\n- List item 1\n- List item 2\n\n```ruby\ncode_example = 'hello world'\n```" }
    end
    
    trait :announcement do
      category { "announcement" }
    end
    
    trait :business_tips do
      category { "business-tips" }
    end
  end
end 
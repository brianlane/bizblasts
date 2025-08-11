ActiveAdmin.register BlogPost do
  permit_params :title, :slug, :excerpt, :content, :author_name, :author_email,
                :category, :featured_image_url, :featured_image, :published, :published_at, :release_date, :remove_featured_image

  index do
    selectable_column
    id_column
    column :title do |post|
      link_to post.title, admin_blog_post_path(post)
    end
    column :category do |post|
      status_tag(post.category_display_name, class: "category") if post.category.present?
    end
    column :author_name
    column :published do |post|
      status_tag(post.published? ? "Published" : "Draft", class: post.published? ? "published" : "draft")
    end
    column :published_at do |post|
      if post.published_at
        content_tag :span, post.published_at.strftime("%B %d, %Y"), 
                    data: { timestamp: post.published_at.iso8601 }
      end
    end
    column "Preview" do |post|
      if post.published?
        link_to "View", post.url_path, target: "_blank", class: "button"
      else
        "Not published"
      end
    end
    actions
  end

  filter :title
  filter :category, as: :select, collection: [
    ['Release Notes', 'release'],
    ['Feature Announcements', 'feature'],
    ['Tutorials', 'tutorial'],
    ['Announcements', 'announcement'],
    ['Business Tips', 'business-tips'],
    ['Customer Spotlights', 'spotlight'],
    ['Platform Updates', 'platform-updates']
  ]
  filter :author_name
  filter :published
  filter :published_at
  filter :created_at

  form do |f|
    f.inputs "Blog Post Details" do
      f.input :title, hint: "Will auto-generate slug if left blank"
      f.input :slug, hint: "URL-friendly version of the title"
      f.input :author_name
      f.input :author_email
      f.input :category, as: :select, collection: [
        ['Release Notes', 'release'],
        ['Feature Announcements', 'feature'],
        ['Tutorials', 'tutorial'],
        ['Announcements', 'announcement'],
        ['Business Tips', 'business-tips'],
        ['Customer Spotlights', 'spotlight'],
        ['Platform Updates', 'platform-updates']
      ], include_blank: false
      f.input :release_date, hint: "Date to organize posts (optional)"
    end
    
    f.inputs "Featured Image" do
      # Show current uploaded file if it exists
      if f.object.featured_image.attached?
        li class: 'input file optional' do
          label 'Current Uploaded Image', class: 'label'
          div class: 'current-file-info' do
            strong "Currently uploaded: #{f.object.featured_image.filename}"
            div class: 'file-meta' do
              "Size: #{number_to_human_size(f.object.featured_image.byte_size)} | " +
              "Type: #{f.object.featured_image.content_type}"
            end
            div class: 'remove-file-option' do
              f.check_box :remove_featured_image
              f.label :remove_featured_image, 'Remove this uploaded image'
            end
          end
        end
      end
      
      f.input :featured_image, as: :file, 
              hint: raw("Upload an image file. Supports PNG, JPEG, GIF, WebP. Max size: 15MB.<br/>
                        <strong>Note:</strong> If both upload and URL are provided, the uploaded file takes priority.")
      f.input :featured_image_url, 
              hint: "Alternative: Full URL to featured image (used only if no file is uploaded above)"
    end
    
    f.inputs "Content" do
      f.input :excerpt, as: :text, input_html: { rows: 4 }, 
              hint: "Short summary shown in blog listing and social media. Supports Markdown formatting."
      
      # Custom content field with integrated toolbar
      li class: 'input text optional' do
        label 'Content', for: 'blog_post_content', class: 'label'
        
        # Debug script to log when elements are rendered
        script do
          raw """
            //console.log('📝 ActiveAdmin form rendering markdown editor elements...');
            //console.log('📝 Testing if JS works - window object:', typeof window);
            //console.log('📝 Testing if JS works - document object:', typeof document);
            //console.log('📝 Testing basic JS functionality...');
            
            // Try to manually trigger markdown editor initialization if it exists
            setTimeout(() => {
              //console.log('📝 Checking for MarkdownEditor class...');
              if (window.MarkdownEditor) {
                //console.log('📝 MarkdownEditor class found in window!');
                try {
                  window.manualEditor = new window.MarkdownEditor();
                  //console.log('📝 Manual MarkdownEditor created successfully');
                } catch (e) {
                  //console.error('📝 Error creating manual MarkdownEditor:', e);
                }
              } else {
                //console.log('📝 MarkdownEditor class NOT found in window');
                //console.log('📝 Available in window:', Object.keys(window).filter(k => k.includes('Mark')));
              }
            }, 500);
          """
        end
        
        # Add the rich editor toolbar ABOVE the textarea
        div class: 'markdown-editor-container', style: 'margin-bottom: 10px;' do
          div class: 'markdown-editor-toolbar', style: 'margin-bottom: 0; border-bottom: none; border-bottom-left-radius: 0; border-bottom-right-radius: 0;' do
            # Text Formatting Group
            div class: 'editor-group' do
              button '**B**', type: 'button', class: 'editor-btn bold-btn', title: 'Bold (Ctrl+B)'
              button '*I*', type: 'button', class: 'editor-btn italic-btn', title: 'Italic (Ctrl+I)'
              button '`Code`', type: 'button', class: 'editor-btn code-btn', title: 'Inline Code (Ctrl+K)'
            end
            
            # Headers Group
            div class: 'editor-group' do
              button 'H1', type: 'button', class: 'editor-btn h1-btn', title: 'Heading 1'
              button 'H2', type: 'button', class: 'editor-btn h2-btn', title: 'Heading 2'
              button 'H3', type: 'button', class: 'editor-btn h3-btn', title: 'Heading 3'
            end
            
            # Content Group  
            div class: 'editor-group' do
              button 'Link', type: 'button', class: 'editor-btn link-btn', title: 'Link (Ctrl+L)'
              button 'Image', type: 'button', class: 'editor-btn image-btn', title: 'Image'
              button 'Quote', type: 'button', class: 'editor-btn quote-btn', title: 'Blockquote'
              button '```', type: 'button', class: 'editor-btn codeblock-btn', title: 'Code Block'
            end
            
            # Lists Group
            div class: 'editor-group' do
              button '• List', type: 'button', class: 'editor-btn ul-btn', title: 'Bullet List'
              button '1. List', type: 'button', class: 'editor-btn ol-btn', title: 'Numbered List'
              button 'Table', type: 'button', class: 'editor-btn table-btn', title: 'Table'
            end
            
            # Preview Toggle
            div class: 'editor-group', style: 'margin-left: auto;' do
              button 'Preview', type: 'button', class: 'editor-btn preview-btn', title: 'Toggle Preview'
            end
          end
          
          # Textarea immediately below toolbar
          f.text_area :content, 
                      rows: 25, 
                      class: 'markdown-editor',
                      style: 'border-top-left-radius: 0; border-top-right-radius: 0; border-top: none; margin-top: 0;',
                      data: { 
                        'markdown-editor': true,
                        'editor-mode': 'markdown'
                      }
          
          # Preview area
          div id: 'content-preview', style: 'display: none; margin-top: 0; border-top: none; border-top-left-radius: 0; border-top-right-radius: 0;' do
            "Preview will appear here..."
          end
          

        end
        
        p class: 'inline-hints' do
          raw("Full blog post content. Supports full <strong>Markdown</strong> and HTML including:<br/>
               • Headers (# ## ###), Lists (- * +), **Bold**, *Italic*<br/>
               • Code blocks with syntax highlighting: ```ruby, ```javascript, ```sql<br/>
               • Tables, blockquotes (>), links [text](url), images ![alt](url)<br/>
               • Inline code `like this`, strikethrough ~~text~~<br/>
               • HTML tags: &lt;div&gt;, &lt;p&gt;, &lt;strong&gt;, &lt;em&gt;, etc.")
        end
      end
    end
    
    f.inputs "Publishing" do
      f.input :published, hint: "Check to make this post visible on the blog"
      f.input :published_at, as: :datetime_picker, 
              hint: "Leave blank to auto-set when published"
    end
    
    f.actions
  end

  show do
    attributes_table do
      row :title
      row :slug
      row :category do |post|
        status_tag(post.category_display_name, class: "category") if post.category.present?
      end
      row :author_name
      row :author_email
      row :featured_image do |post|
        if post.featured_image_for_display
          div do
            image_tag post.featured_image_for_display, style: "max-width: 300px; height: auto;"
          end
          div do
            small "Source: Uploaded file"
          end
        elsif post.featured_image_fallback_url
          div do
            image_tag post.featured_image_fallback_url, style: "max-width: 300px; height: auto;"
          end
          div do
            small "Source: URL - #{post.featured_image_fallback_url}"
          end
        else
          "No featured image"
        end
      end
      row :published do |post|
        status_tag(post.published? ? "Published" : "Draft", class: post.published? ? "published" : "draft")
      end
      row :published_at do |post|
        if post.published_at
          content_tag :span, post.published_at.strftime("%B %d, %Y at %I:%M %p UTC"), 
                      data: { timestamp: post.published_at.iso8601 }
        end
      end
      row :release_date
      row :created_at do |post|
        content_tag :span, post.created_at.strftime("%B %d, %Y at %I:%M %p UTC"), 
                    data: { timestamp: post.created_at.iso8601 }
      end
      row :updated_at do |post|
        content_tag :span, post.updated_at.strftime("%B %d, %Y at %I:%M %p UTC"), 
                    data: { timestamp: post.updated_at.iso8601 }
      end
    end
    
    panel "Excerpt Preview" do
      div class: "markdown-content", style: "padding: 15px; background: #f9f9f9; border-radius: 5px;" do
        raw blog_post.rendered_excerpt
      end
    end
    
    panel "Content Preview" do
      div class: "markdown-content", style: "max-height: 500px; overflow-y: auto; border: 1px solid #ddd; padding: 15px; background: white; border-radius: 5px;" do
        raw blog_post.rendered_content
      end
    end
    
    panel "URLs" do
      if blog_post.published?
        ul do
          li link_to "View on Blog", blog_post.url_path, target: "_blank"
          li "Canonical URL: #{request.protocol}#{request.host_with_port}#{blog_post.url_path}"
        end
      else
        em "Post must be published to generate URLs"
      end
    end
  end

  action_item :view_on_site, only: :show do
    if blog_post.published?
      link_to "View on Blog", blog_post.url_path, target: "_blank", class: "button"
    end
  end

  action_item :duplicate, only: :show do
    link_to "Duplicate", new_admin_blog_post_path(
      duplicate_from: blog_post.slug
    ), class: "button"
  end

  controller do
    before_action :handle_duplicate, only: [:new]

    private

    def find_resource
      scoped_collection.find_by!(slug: params[:id])
    end

    def handle_duplicate
      if params[:duplicate_from].present?
        source = BlogPost.find_by!(slug: params[:duplicate_from])
        @blog_post = BlogPost.new(
          title: "Copy of #{source.title}",
          excerpt: source.excerpt,
          content: source.content,
          author_name: source.author_name,
          author_email: source.author_email,
          category: source.category,
          published: false
        )
      end
    end
  end
end 
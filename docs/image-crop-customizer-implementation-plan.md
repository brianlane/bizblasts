# Image Crop Customizer Implementation Plan

## Overview

Add user-controlled image cropping to BizBlasts using a hybrid approach: client-side preview with server-side processing. This feature will be mandatory for all image upload locations where BizBlasts currently resizes images.

**Approach:** Option C - Hybrid (Client preview + Server processing)

---

## Configuration Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Re-crop existing images | No | Simpler implementation, no original storage needed |
| Aspect ratios | Popular only | 1:1, 16:9, 4:3, Free |
| Mandatory/Optional | Mandatory where resizing occurs | Consistent UX, ensures quality |
| Smart crop suggestions | No | Keep scope focused |
| Max image dimension | 4096×4096 | Browser compatibility, memory safety |

---

## Maximum Image Dimension: 4096×4096

### Why This Limit

**Browser Canvas Limits:**
- Chrome: 16,384×16,384
- Firefox: 11,180×11,180
- Safari Desktop: 16,384×16,384
- **Safari iOS (older): 4,096×4,096** ← Limiting factor
- Safari iOS (newer): 8,192×8,192

**Memory Calculation:**
- 4096×4096 × 4 bytes = ~67MB uncompressed
- With 2× processing overhead = ~134MB
- Safe for devices with 2GB+ RAM

**Coverage:**
- iPhone photos: 4032×3024 ✓ (fits within limit)
- Android photos: 4000×3000 ✓
- Mid-range DSLR: 6000×4000 → Auto-scaled to fit
- High-end DSLR: 8256×5504 → Auto-scaled to fit

**Implementation:**
- Images larger than 4096 in any dimension are automatically scaled down client-side before cropper loads
- User never sees this scaling - transparent UX
- Original quality preserved for images within limit

---

## Aspect Ratios by Context

| Image Type | Default | Available Options |
|------------|---------|-------------------|
| Business Logo | 1:1 | 1:1 only (locked) |
| Staff Photo | 1:1 | 1:1 only (locked) |
| Product Images | 1:1 | Free, 1:1, 4:3 |
| Service Images | 1:1 | Free, 1:1, 4:3 |
| Gallery Photos | Free | Free, 1:1, 16:9, 4:3 |
| Blog Featured | 16:9 | 16:9, 3:2 |

---

## Technical Architecture

### Data Flow

```
User selects file
       ↓
Client: Check dimensions
       ↓
[If > 4096px] → Scale down to fit
       ↓
Client: Show cropper modal
       ↓
User adjusts crop area
       ↓
Client: Generate preview (canvas)
       ↓
Client: Capture crop coordinates {x, y, width, height, rotate}
       ↓
User clicks "Apply"
       ↓
Client: Store crop data in hidden field
       ↓
Client: Show cropped preview in form
       ↓
User submits form
       ↓
Server: Receive original file + crop JSON
       ↓
Server: ImageCropService applies crop
       ↓
Server: ProcessImageJob generates variants
       ↓
Server: Store final cropped image
```

### Key Components

1. **`image_cropper_controller.js`** - Stimulus controller
2. **`ImageCropService`** - Ruby service for server-side cropping
3. **`_image_cropper_modal.html.erb`** - Reusable modal partial
4. **Modified upload forms** - Integration points

---

## Phase 1: Core Infrastructure (4-6 hours)

### 1.1 Install Cropper.js

```bash
yarn add cropperjs
```

### 1.2 Create Stimulus Controller

**File:** `app/javascript/controllers/image_cropper_controller.js`

**Responsibilities:**
- Load selected image into cropper
- Handle dimension check and auto-scaling
- Manage aspect ratio changes
- Export crop coordinates
- Generate preview thumbnail

**Stimulus Targets:**
```javascript
static targets = [
  "fileInput",      // Original file input (hidden after init)
  "preview",        // Image element for cropper
  "cropData",       // Hidden field storing JSON crop coordinates
  "modal",          // Cropper modal container
  "thumbnail",      // Preview thumbnail in form
  "aspectRatio",    // Aspect ratio selector (if applicable)
  "zoomRange"       // Zoom slider
]
```

**Stimulus Values:**
```javascript
static values = {
  aspectRatio: Number,      // Default aspect ratio (0 = free)
  lockAspectRatio: Boolean, // Whether user can change ratio
  maxDimension: { type: Number, default: 4096 },
  minCropSize: { type: Number, default: 100 }
}
```

**Key Methods:**
```javascript
// Lifecycle
connect()           // Initialize, set up event listeners
disconnect()        // Cleanup cropper instance

// User Actions
openCropper()       // Show modal with image
applyCrop()         // Save crop data, close modal, show preview
cancelCrop()        // Discard changes, close modal
resetCrop()         // Reset to original/default crop
setAspectRatio(e)   // Change aspect ratio
zoom(e)             // Handle zoom in/out

// Internal
loadImage(file)     // Load file, scale if needed, init cropper
scaleImageIfNeeded(img) // Scale to max 4096px
getCropData()       // Extract {x, y, width, height, rotate}
generateThumbnail() // Create preview for form display
```

### 1.3 Import in Application

**File:** `app/javascript/application.js`

```javascript
import "cropperjs/dist/cropper.css"
// Controller auto-registered via stimulus manifest
```

---

## Phase 2: Backend Service (3-4 hours)

### 2.1 Create ImageCropService

**File:** `app/services/image_crop_service.rb`

```ruby
# frozen_string_literal: true

class ImageCropService
  # Applies crop transformation to an Active Storage attachment
  #
  # @param attachment [ActiveStorage::Attached::One] The image attachment
  # @param crop_params [Hash] Crop coordinates {x:, y:, width:, height:, rotate:}
  # @return [Boolean] Success status
  #
  # Usage:
  #   ImageCropService.new(product.images.first, crop_params).call
  
  MAX_DIMENSION = 4096
  
  def initialize(attachment, crop_params)
    @attachment = attachment
    @crop_params = normalize_params(crop_params)
  end
  
  def call
    return false unless valid?
    
    process_crop
    true
  rescue => e
    Rails.logger.error "[IMAGE_CROP] Failed: #{e.message}"
    false
  end
  
  private
  
  def valid?
    @attachment.attached? && 
      @crop_params[:width].to_i > 0 && 
      @crop_params[:height].to_i > 0
  end
  
  def normalize_params(params)
    {
      x: params[:x].to_i,
      y: params[:y].to_i,
      width: params[:width].to_i,
      height: params[:height].to_i,
      rotate: params[:rotate].to_i
    }
  end
  
  def process_crop
    @attachment.blob.open do |tempfile|
      cropped = ImageProcessing::MiniMagick
        .source(tempfile)
        .rotate(@crop_params[:rotate]) if @crop_params[:rotate] != 0
        .crop(
          @crop_params[:x],
          @crop_params[:y],
          @crop_params[:width],
          @crop_params[:height]
        )
        .resize_to_limit(MAX_DIMENSION, MAX_DIMENSION)
        .call
      
      # Replace blob with cropped version
      new_blob = ActiveStorage::Blob.create_and_upload!(
        io: File.open(cropped),
        filename: @attachment.blob.filename,
        content_type: @attachment.blob.content_type
      )
      
      old_blob = @attachment.blob
      @attachment.update!(blob: new_blob)
      old_blob.purge_later
    end
  end
end
```

### 2.2 Update ProcessImageJob

**File:** `app/jobs/process_image_job.rb`

No changes needed - crops happen before this job runs. The job receives already-cropped images.

---

## Phase 3: UI Components (6-8 hours)

### 3.1 Cropper Modal Partial

**File:** `app/views/shared/_image_cropper_modal.html.erb`

```erb
<%# 
  Image Cropper Modal
  
  Usage:
    <%= render 'shared/image_cropper_modal', 
        modal_id: "product_image_cropper",
        aspect_ratio: 1,           # 0 = free, 1 = 1:1, 1.777 = 16:9, 1.333 = 4:3
        lock_aspect_ratio: false,
        available_ratios: ["free", "1:1", "16:9", "4:3"]
    %>
%>
<% modal_id ||= "image_cropper_modal" %>
<% aspect_ratio ||= 0 %>
<% lock_aspect_ratio ||= false %>
<% available_ratios ||= ["free", "1:1"] %>

<div id="<%= modal_id %>" 
     class="hidden fixed inset-0 z-50 overflow-y-auto"
     data-image-cropper-target="modal"
     aria-labelledby="cropper-title" 
     role="dialog" 
     aria-modal="true">
  
  <!-- Backdrop -->
  <div class="fixed inset-0 bg-gray-900 bg-opacity-75 transition-opacity"
       data-action="click->image-cropper#cancelCrop"></div>
  
  <!-- Modal Panel -->
  <div class="flex min-h-full items-center justify-center p-4">
    <div class="relative bg-white rounded-xl shadow-2xl w-full max-w-3xl overflow-hidden"
         data-action="click->image-cropper#stopPropagation">
      
      <!-- Header -->
      <div class="px-6 py-4 border-b border-gray-200 bg-gray-50">
        <div class="flex items-center justify-between">
          <h3 id="cropper-title" class="text-lg font-semibold text-gray-900">
            Crop Image
          </h3>
          <button type="button" 
                  class="text-gray-400 hover:text-gray-600 transition-colors"
                  data-action="click->image-cropper#cancelCrop">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
            </svg>
          </button>
        </div>
      </div>
      
      <!-- Cropper Area -->
      <div class="p-4 bg-gray-900">
        <div class="relative w-full" style="height: 400px;">
          <img data-image-cropper-target="preview" 
               class="max-w-full max-h-full"
               src=""
               alt="Image to crop">
        </div>
      </div>
      
      <!-- Controls -->
      <div class="px-6 py-4 border-t border-gray-200 bg-gray-50">
        <div class="flex flex-col sm:flex-row items-center justify-between gap-4">
          
          <!-- Aspect Ratio Selector (if not locked) -->
          <% unless lock_aspect_ratio %>
            <div class="flex items-center gap-2">
              <span class="text-sm font-medium text-gray-700">Aspect Ratio:</span>
              <div class="flex gap-1">
                <% available_ratios.each do |ratio| %>
                  <% 
                    ratio_value = case ratio
                    when "free" then 0
                    when "1:1" then 1
                    when "16:9" then 1.7778
                    when "4:3" then 1.3333
                    when "3:2" then 1.5
                    else 0
                    end
                  %>
                  <button type="button"
                          class="px-3 py-1.5 text-sm font-medium rounded-md transition-colors
                                 data-[active]:bg-primary data-[active]:text-white
                                 bg-white border border-gray-300 text-gray-700 hover:bg-gray-50"
                          data-action="click->image-cropper#setAspectRatio"
                          data-ratio="<%= ratio_value %>">
                    <%= ratio.capitalize %>
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
          
          <!-- Zoom Controls -->
          <div class="flex items-center gap-3">
            <button type="button" 
                    class="p-2 rounded-md bg-white border border-gray-300 hover:bg-gray-50 transition-colors"
                    data-action="click->image-cropper#zoomOut"
                    title="Zoom Out">
              <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM13 10H7"/>
              </svg>
            </button>
            <input type="range" 
                   min="0.1" max="3" step="0.1" value="1"
                   class="w-24"
                   data-image-cropper-target="zoomRange"
                   data-action="input->image-cropper#zoomTo">
            <button type="button" 
                    class="p-2 rounded-md bg-white border border-gray-300 hover:bg-gray-50 transition-colors"
                    data-action="click->image-cropper#zoomIn"
                    title="Zoom In">
              <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM10 7v3m0 0v3m0-3h3m-3 0H7"/>
              </svg>
            </button>
          </div>
          
          <!-- Rotate Controls -->
          <div class="flex items-center gap-2">
            <button type="button" 
                    class="p-2 rounded-md bg-white border border-gray-300 hover:bg-gray-50 transition-colors"
                    data-action="click->image-cropper#rotateLeft"
                    title="Rotate Left">
              <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6"/>
              </svg>
            </button>
            <button type="button" 
                    class="p-2 rounded-md bg-white border border-gray-300 hover:bg-gray-50 transition-colors"
                    data-action="click->image-cropper#rotateRight"
                    title="Rotate Right">
              <svg class="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 10h-10a8 8 0 00-8 8v2M21 10l-6 6m6-6l-6-6"/>
              </svg>
            </button>
          </div>
        </div>
      </div>
      
      <!-- Footer Actions -->
      <div class="px-6 py-4 border-t border-gray-200 flex justify-end gap-3">
        <button type="button"
                class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
                data-action="click->image-cropper#resetCrop">
          Reset
        </button>
        <button type="button"
                class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
                data-action="click->image-cropper#cancelCrop">
          Cancel
        </button>
        <button type="button"
                class="px-4 py-2 text-sm font-medium text-white bg-primary rounded-lg hover:bg-primary/90 transition-colors"
                data-action="click->image-cropper#applyCrop">
          Apply Crop
        </button>
      </div>
    </div>
  </div>
</div>
```

### 3.2 Form Integration Pattern

For each form, replace the current file input with the cropper-enabled version:

```erb
<!-- Example: Product Image Upload with Cropper -->
<div data-controller="image-cropper"
     data-image-cropper-aspect-ratio-value="1"
     data-image-cropper-lock-aspect-ratio-value="false"
     data-image-cropper-max-dimension-value="4096">
  
  <!-- Hidden file input -->
  <%= form.file_field :images, 
        multiple: true,
        accept: "image/png,image/jpeg,image/gif,image/webp,image/heic,image/heif",
        class: "hidden",
        data: { 
          image_cropper_target: "fileInput",
          action: "change->image-cropper#fileSelected"
        } %>
  
  <!-- Hidden crop data field -->
  <%= form.hidden_field :crop_data, 
        data: { image_cropper_target: "cropData" } %>
  
  <!-- Upload Button -->
  <button type="button" 
          class="upload-button"
          data-action="click->image-cropper#triggerFileSelect">
    Choose Image
  </button>
  
  <!-- Preview Thumbnail (shown after crop) -->
  <div data-image-cropper-target="thumbnail" class="hidden">
    <img src="" alt="Cropped preview" class="w-24 h-24 object-cover rounded-lg">
  </div>
  
  <!-- Cropper Modal -->
  <%= render 'shared/image_cropper_modal',
      modal_id: "product_cropper",
      aspect_ratio: 1,
      lock_aspect_ratio: false,
      available_ratios: ["free", "1:1", "4:3"] %>
</div>
```

---

## Phase 4: Form Updates (2-3 hours)

### Forms to Update

| Form | File | Default Ratio | Lock Ratio |
|------|------|---------------|------------|
| Business Logo | `settings/business/edit.html.erb` | 1:1 | Yes |
| Staff Photo | `staff_members/_form.html.erb` | 1:1 | Yes |
| Product Images | `products/_form.html.erb` | 1:1 | No |
| Service Images | `services/_form.html.erb` | 1:1 | No |
| Gallery Photos | `gallery/index.html.erb` | Free | No |

### Controller Updates

Add `crop_data` to strong params and call `ImageCropService` after save:

```ruby
# Example: ProductsController

def product_params
  params.require(:product).permit(
    :name, :description, :price, # ... existing params
    :crop_data,  # NEW: JSON string with crop coordinates
    images_attributes: [:id, :_destroy, :primary, :position, :crop_data]
  )
end

private

def apply_image_crops
  return unless params[:product][:crop_data].present?
  
  crop_data = JSON.parse(params[:product][:crop_data])
  crop_data.each do |image_index, crop_params|
    image = @product.images[image_index.to_i]
    ImageCropService.new(image, crop_params).call if image
  end
end
```

---

## Phase 5: Mobile Optimization (3-4 hours)

### Touch Support

Cropper.js includes built-in touch support:
- Drag to move crop area
- Pinch to zoom
- Two-finger rotate

### Responsive Modal

```css
/* Mobile-first modal styles */
@media (max-width: 640px) {
  .cropper-modal {
    /* Full screen on mobile */
    padding: 0;
  }
  
  .cropper-panel {
    max-width: 100%;
    max-height: 100vh;
    border-radius: 0;
  }
  
  .cropper-area {
    height: 60vh;
  }
  
  .cropper-controls {
    flex-direction: column;
    gap: 1rem;
  }
}
```

### Performance

- Use `requestAnimationFrame` for smooth zoom
- Debounce crop data updates (100ms)
- Use CSS transforms for preview (GPU accelerated)

---

## File Changes Summary

### New Files

```
app/javascript/controllers/image_cropper_controller.js
app/services/image_crop_service.rb
app/views/shared/_image_cropper_modal.html.erb
spec/services/image_crop_service_spec.rb
spec/javascript/controllers/image_cropper_controller_spec.js
docs/image-crop-customizer-implementation-plan.md (this file)
```

### Modified Files

```
package.json                                          # Add cropperjs
app/javascript/application.js                         # Import cropper CSS
app/views/business_manager/settings/business/edit.html.erb
app/views/business_manager/staff_members/_form.html.erb
app/views/business_manager/products/_form.html.erb
app/views/business_manager/services/_form.html.erb
app/views/business_manager/gallery/index.html.erb
app/controllers/business_manager/settings/business_controller.rb
app/controllers/business_manager/staff_members_controller.rb
app/controllers/business_manager/products_controller.rb
app/controllers/business_manager/services_controller.rb
app/controllers/business_manager/gallery_controller.rb
```

---

## Testing Plan

### Unit Tests

- `ImageCropService` - crop application, edge cases, invalid params
- Stimulus controller - file handling, crop data export

### Integration Tests

- Product create with cropped image
- Service update with cropped image
- Logo upload with mandatory square crop
- Gallery photo upload with various aspect ratios

### Manual Testing Checklist

- [ ] Upload image smaller than 4096px - no scaling
- [ ] Upload image larger than 4096px - auto-scaled
- [ ] Apply 1:1 crop to rectangular image
- [ ] Apply 16:9 crop
- [ ] Apply free-form crop
- [ ] Zoom in/out functionality
- [ ] Rotate left/right
- [ ] Reset crop
- [ ] Cancel without saving
- [ ] Mobile touch interactions
- [ ] HEIC file handling (should still work)

---

## Estimated Timeline

| Phase | Tasks | Hours |
|-------|-------|-------|
| Phase 1 | Cropper.js setup, Stimulus controller | 4-6 |
| Phase 2 | ImageCropService, backend integration | 3-4 |
| Phase 3 | Modal UI, form integration pattern | 6-8 |
| Phase 4 | Update all 5 forms + controllers | 2-3 |
| Phase 5 | Mobile optimization, touch support | 3-4 |
| Testing | Unit + integration + manual | 4-6 |
| **Total** | | **22-31 hours** |

---

## Future Enhancements (Out of Scope)

- Re-crop existing images (requires storing originals)
- Smart crop with face detection
- Batch crop for multiple images
- Crop presets per business
- Undo/redo in cropper



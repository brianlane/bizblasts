# Analytics Fixes - Round 3

Final analytics errors fixed after Round 2 deployment.

## Summary

Fixed 8 remaining analytics issues across 3 views:
- ✅ Products Analytics (missing template + missing partial)
- ✅ Inventory Analytics (missing association chain + incorrect stock_movements schema)
- ✅ Marketing Analytics (nil variable + 2 incorrect iterations)

## Issues Fixed

### 1. Products: Missing Template for Products Analytics View

**Error:**
```
ActionController::MissingExactTemplate: BusinessManager::AnalyticsController#products is missing a template for request formats: text/html
```

**Location:** `app/views/business_manager/analytics/products.html.erb` (file didn't exist)

**Root Cause:** The products analytics action existed in the controller, but there was no corresponding view template.

**Fix:** Created complete view template with:
- Header with period selector
- 4 metrics summary cards (Total Orders, Total Revenue, Average Order Value, Items Sold)
- Top Products table showing product name, quantity sold, and revenue
- Cart Abandonment section with 3 metrics (Carts Created, Checkouts Started, Abandonment Rate)

**Files Changed:**
- `app/views/business_manager/analytics/products.html.erb` (new file, 92 lines)

---

### 1b. Products: Missing Period Selector Partial

**Error:**
```
ActionView::Template::Error: Missing partial business_manager/analytics/_period_selector
```

**Location:** `app/views/business_manager/analytics/products.html.erb:4`

**Root Cause:** The products view tried to render a `_period_selector` partial that doesn't exist anywhere in the application.

**Fix:** Removed the `<%= render 'period_selector' %>` line from the products view, since the products controller doesn't use a period parameter.

**Code:**
```ruby
# Removed line 4:
<%= render 'period_selector' %>
```

**Files Changed:**
- `app/views/business_manager/analytics/products.html.erb` (removed line 4)

---

### 2. Inventory: Business Missing stock_movements Association Chain

**Error:**
```
ActiveRecord::HasManyThroughSourceAssociationNotFoundError: Could not find the source association(s) "stock_movement" or :stock_movements in model Product
```

**Location:** `app/services/analytics/inventory_intelligence_service.rb:237`

**Root Cause:** The Inventory Intelligence Service was calling `business.stock_movements`, but:
1. The Business model had `has_many :stock_movements, through: :products`
2. BUT the Product model was missing `has_many :stock_movements`
3. This broke the association chain

The association chain needs to be: Business → Products → StockMovements

**Fix:** Added `has_many :stock_movements` to Product model, which allows the Business `through: :products` association to work.

**Code:**
```ruby
# app/models/product.rb (line 17)
has_many :product_variants, -> { order(:id) }, dependent: :destroy
has_many :stock_movements, dependent: :destroy  # <-- Added

# app/models/business.rb (line 186) - Already added in previous fix
has_many :products, dependent: :destroy
has_many :stock_movements, through: :products
```

**Files Changed:**
- `app/models/product.rb` (added line 17)
- `app/models/business.rb` (line 186, added earlier)

---

### 2b. Inventory: Incorrect StockMovement Schema References

**Error:**
```
PG::UndefinedColumn: ERROR: column "reason" does not exist
LINE 1: SELECT COUNT(*) AS "count_all", "reason" AS "reason" FROM "stock_movements"...
```

**Location:** `app/services/analytics/inventory_intelligence_service.rb:195`

**Root Cause:** The service was referencing columns and associations that don't exist in the StockMovement model:
- Tried to group by `reason` column (doesn't exist - should be `notes`)
- Tried to access `movement.product_variant` (doesn't exist - StockMovement belongs_to :product, not product_variant)
- Used incorrect movement_type filters

**Actual StockMovement schema:**
```ruby
# stock_movements table columns:
- product_id (belongs_to :product)
- movement_type (string)
- quantity (integer)
- notes (text) # NOT reason
- reference_id, reference_type (polymorphic)
```

**Fix:** Updated the `stock_movement_summary` method to use correct columns and associations.

**Code:**
```ruby
# Before (lines 190-205):
{
  total_movements: movements.count,
  stock_in: movements.where(movement_type: 'in').sum(:quantity),
  stock_out: movements.where(movement_type: 'out').sum(:quantity),
  adjustments: movements.where(movement_type: 'adjustment').sum(:quantity),
  by_reason: movements.group(:reason).count,  # reason doesn't exist
  recent_movements: movements.order(created_at: :desc).limit(20).map do |movement|
    {
      date: movement.created_at,
      product_name: movement.product_variant&.product&.name,  # product_variant doesn't exist
      variant_name: movement.product_variant&.name,
      movement_type: movement.movement_type,
      quantity: movement.quantity,
      reason: movement.reason  # reason doesn't exist
    }
  end
}

# After:
{
  total_movements: movements.count,
  stock_in: movements.inbound.sum(:quantity),  # Use scope
  stock_out: movements.outbound.sum(:quantity),  # Use scope
  adjustments: movements.where(movement_type: 'adjustment').sum(:quantity),
  by_type: movements.group(:movement_type).count,  # Group by movement_type instead
  recent_movements: movements.order(created_at: :desc).limit(20).map do |movement|
    {
      date: movement.created_at,
      product_name: movement.product&.name,  # Direct belongs_to :product
      movement_type: movement.movement_type,
      quantity: movement.quantity,
      notes: movement.notes  # Use notes instead of reason
    }
  end
}
```

**Files Changed:**
- `app/services/analytics/inventory_intelligence_service.rb` (lines 190-205)

---

### 3. Marketing: @marketing_summary Instance Variable Not Set

**Error:**
```
ActionView::Template::Error: undefined method '[]' for nil
NoMethodError: undefined method '[]' for nil:NilClass
@marketing_summary[:total_spend]
```

**Location:** `app/views/business_manager/analytics/marketing/index.html.erb:95, 110, 125, 142, 150`

**Root Cause:** The Marketing controller's index action sets `@spend_efficiency`, but the view was trying to access `@marketing_summary` which was never set.

**View Requirements:**
The view needed the following fields from `@marketing_summary`:
- `total_spend` - Total campaign spend
- `total_revenue` - Total revenue generated
- `avg_roi` - Average return on investment
- `total_conversions` - Total conversions
- `conversion_rate` - Average conversion rate across campaigns

**Fix:** Added code to the controller's index action to set `@marketing_summary` by:
1. Taking `@spend_efficiency` data (total_spend, total_revenue, total_conversions, roi)
2. Calculating average conversion rate from campaigns
3. Merging into `@marketing_summary` with proper field mappings

**Code:**
```ruby
# app/controllers/business_manager/analytics/marketing_controller.rb (lines 16-26)
# Set @marketing_summary for view compatibility
avg_conversion_rate = if @campaigns_summary.any?
                       @campaigns_summary.sum { |c| c[:conversion_rate] } / @campaigns_summary.size
                     else
                       0.0
                     end

@marketing_summary = @spend_efficiency.merge(
  avg_roi: @spend_efficiency[:roi],
  conversion_rate: avg_conversion_rate
)
```

**Files Changed:**
- `app/controllers/business_manager/analytics/marketing_controller.rb` (added lines 16-26)

---

### 3b. Marketing: Incorrect Channel Performance Iteration

**Error:**
```
NoMethodError: undefined method '[]' for nil
```

**Location:** `app/views/business_manager/analytics/marketing/index.html.erb:229`

**Root Cause:** The view was iterating over `@channel_performance` incorrectly:
- The service returns an **array** of hashes: `[{channel: "Email", revenue: 100, conversions: 5}, ...]`
- But the view was treating it like a **hash**: `@channel_performance.each do |channel, data|`
- This caused `data` to be nil, leading to the error when accessing `data[:conversions]`

Additionally, the view tried to display `data[:roi]` which doesn't exist in the returned hash structure.

**Fix:** Changed the iteration to correctly handle the array of hashes and display available fields.

**Code:**
```ruby
# Before (line 217):
<% @channel_performance.each do |channel, data| %>
  <h3><%= channel %></h3>
  <div><%= data[:revenue] %></div>
  <div><%= data[:conversions] %></div>
  <div><%= data[:roi] %></div>  # roi doesn't exist

# After:
<% @channel_performance.each do |data| %>
  <h3><%= data[:channel] %></h3>
  <div><%= data[:revenue] %></div>
  <div><%= data[:conversions] %></div>
  <div><%= data[:conversion_rate] %></div>  # Use actual field
```

**Files Changed:**
- `app/views/business_manager/analytics/marketing/index.html.erb` (lines 217-239)

---

### 3c. Marketing: Incorrect Acquisition Sources Iteration

**Error:**
```
NoMethodError: undefined method '[]' for nil
```

**Location:** `app/views/business_manager/analytics/marketing/index.html.erb:263`

**Root Cause:** Same issue as channel performance - the view was iterating incorrectly:
- The service returns an **array** of hashes: `[{source: "Direct", acquisitions: 10, percentage: 50}, ...]`
- But the view was treating it like a **hash**: `@acquisition_sources.each do |source, data|`
- This caused `data` to be nil

Additionally, the view was looking for `data[:customers]` but the service returns `data[:acquisitions]`.

**Fix:** Changed iteration to correctly handle the array and use correct field names.

**Code:**
```ruby
# Before (line 254):
<% @acquisition_sources.each do |source, data| %>
  <span><%= source %></span>
  <span><%= data[:customers] %> customers</span>  # Wrong field name
  <span><%= data[:percentage] %>%</span>

# After:
<% @acquisition_sources.each do |data| %>
  <span><%= data[:source] %></span>
  <span><%= data[:acquisitions] %> acquisitions</span>  # Correct field name
  <span><%= data[:percentage] %>%</span>
```

**Files Changed:**
- `app/views/business_manager/analytics/marketing/index.html.erb` (lines 254-270)

---

## Testing

After these fixes, test each analytics view:
1. **Products** - `/manage/analytics/products` or from Products tab
2. **Inventory** - `/manage/analytics/inventory`
3. **Marketing** - `/manage/analytics/marketing`

All views should now load without errors.

---

## Files Modified Summary

**Views:**
- `app/views/business_manager/analytics/products.html.erb` (new file, then modified)
- `app/views/business_manager/analytics/marketing/index.html.erb` (2 sections fixed)

**Models:**
- `app/models/business.rb`
- `app/models/product.rb`

**Services:**
- `app/services/analytics/inventory_intelligence_service.rb`

**Controllers:**
- `app/controllers/business_manager/analytics/marketing_controller.rb`

**Total: 6 files modified/created**

---

## Complete Analytics Fix Summary (All Rounds)

### Round 1: 8 Services Fixed
- Revenue Forecast Service
- Operational Efficiency Service
- Staff Performance Service
- Customer Lifecycle Service
- Churn Prediction Service
- Inventory Intelligence Service
- Marketing Performance Service
- Predictive Service

### Round 2: 5 Views Fixed
- ✅ Bookings Analytics (column reference)
- ✅ Products Analytics (LineItem association)
- ✅ Staff Analytics (variable reference)
- ✅ Inventory Analytics (Product method)
- ✅ Marketing Analytics (database columns)

### Round 3: 8 Issues Fixed Across 3 Views
- ✅ Products Analytics (missing template + missing partial)
- ✅ Inventory Analytics (Product association + Business association + schema mismatch)
- ✅ Marketing Analytics (controller variable + channel iteration + acquisition iteration)

**Grand Total: 21 analytics issues fixed across 3 rounds**

---

## Architecture Notes

### Stock Movement Association Chain
StockMovements are accessed through Products with a **complete association chain**:
- `StockMovement belongs_to :product`
- `Product has_many :stock_movements` ✅ **Required for through association**
- `Product belongs_to :business`
- `Business has_many :products`
- `Business has_many :stock_movements, through: :products` ✅

**Critical:** For a `has_many :through` association to work, BOTH models in the chain must have the proper associations:
1. Business needs: `has_many :products` and `has_many :stock_movements, through: :products`
2. Product needs: `has_many :stock_movements` ← **This was missing and caused the error**

To query stock movements for a business:
```ruby
# ✅ Correct approach (after fix):
business.stock_movements.where(created_at: 30.days.ago..Time.current)

# ❌ Incorrect approach (before fix):
# Business had `through: :products` but Product was missing `has_many :stock_movements`
# This caused: ActiveRecord::HasManyThroughSourceAssociationNotFoundError
```

### Marketing Summary Data Flow
The Marketing controller provides data to the view through multiple instance variables:
- `@spend_efficiency` - Marketing spend efficiency metrics
- `@campaigns_summary` - Campaign performance data
- `@marketing_summary` - Consolidated summary for overview cards (derived from above)

The view uses `@marketing_summary` for the main metrics dashboard, which is now properly populated from `@spend_efficiency` with additional calculated fields.

### Channel Performance Data Structure
The `channel_performance` service method returns an **array of hashes**, not a hash:

```ruby
# Service returns:
[
  { channel: "Email", sessions: 100, conversions: 5, revenue: 500.00, conversion_rate: 5.0 },
  { channel: "SMS", sessions: 50, conversions: 3, revenue: 300.00, conversion_rate: 6.0 },
  ...
]

# ✅ Correct iteration:
<% @channel_performance.each do |data| %>
  <%= data[:channel] %>
  <%= data[:conversions] %>
<% end %>

# ❌ Incorrect iteration (before fix):
<% @channel_performance.each do |channel, data| %>
  # This treats it as hash key-value pairs
  # data becomes nil, causing NoMethodError
<% end %>
```

**Available fields:** `:channel`, `:sessions`, `:conversions`, `:conversion_rate`, `:revenue`
**NOT available:** `:roi` (ROI is only available in campaign data, not channel data)

### StockMovement Schema and Associations
The StockMovement model has a specific schema that must be respected:

**Schema:**
```ruby
# stock_movements table:
- product_id (foreign key to products)
- movement_type (string: 'subscription_fulfillment', 'restock', 'adjustment', 'return')
- quantity (integer, can be positive or negative)
- notes (text) # NOT reason
- reference_id, reference_type (polymorphic)
- created_at, updated_at
```

**Associations:**
```ruby
# StockMovement model:
belongs_to :product  # NOT product_variant

# Available scopes:
.inbound    # where('quantity > 0')
.outbound   # where('quantity < 0')
.by_type(type)  # where(movement_type: type)
```

**Common mistakes to avoid:**
- ❌ Accessing `movement.product_variant` - doesn't exist
- ❌ Grouping by `reason` - column is called `notes`
- ❌ Using `movement_type: 'in'` or `'out'` - use scopes `.inbound` / `.outbound` or actual type values
- ✅ Use `movement.product.name` for product name
- ✅ Use `movement.notes` for additional information
- ✅ Group by `movement_type` for categorization

### Acquisition Sources Data Structure
The `acquisition_by_source` service method returns an **array of hashes**:

```ruby
# Service returns:
[
  { source: "Direct", acquisitions: 10, percentage: 50.0, cost_per_acquisition: nil },
  { source: "Organic", acquisitions: 5, percentage: 25.0, cost_per_acquisition: nil },
  { source: "Paid", acquisitions: 5, percentage: 25.0, cost_per_acquisition: 50.00 },
  ...
]

# ✅ Correct iteration:
<% @acquisition_sources.each do |data| %>
  <%= data[:source] %>
  <%= data[:acquisitions] %>
<% end %>
```

**Available fields:** `:source`, `:acquisitions`, `:percentage`, `:cost_per_acquisition`
**NOT available:** `:customers` (the field is `:acquisitions`)

---

## Next Steps

All analytics views should now be functional. Consider:
1. ✅ Products Analytics - Template created
2. ✅ Inventory Analytics - Association added
3. ✅ Marketing Analytics - Variable populated
4. 🧪 Run full analytics test suite
5. 📊 Verify all analytics dashboards load correctly
6. 🚀 Deploy to production

---

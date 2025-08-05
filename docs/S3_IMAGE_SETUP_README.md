# S3 Image Upload Configuration - 15MB Support

This document outlines the implementation of S3 image storage with 15MB file support and CloudFront CDN integration for BizBlasts.

## Environment Variables Required

Add these environment variables to your production environment:

```bash
# AWS S3 Configuration
IAM_AWS_ACCESS_KEY=your_aws_access_key
IAM_AWS_SECRET_ACCESS_KEY=your_aws_secret_key
AWS_REGION=us-west-2  # or your preferred region
AWS_BUCKET=bizblasts-production-images

# CloudFront CDN (Optional but recommended)
ACTIVE_STORAGE_ASSET_HOST=https://d1234567890.cloudfront.net  # Your CloudFront domain
```

## Features Implemented

### 1. Large File Support (15MB)
- **File Size Limit**: Increased from 5MB to 15MB
- **Supported Formats**: PNG, JPEG, JPG, GIF, WebP
- **Server Configuration**: Puma timeouts and content length limits updated
- **Client Validation**: JavaScript validation for file size and format

### 2. Image Processing & Optimization
- **Automatic Variants**: thumb (300x300), medium (800x800), large (1200x1200)
- **Background Processing**: `ProcessImageJob` using Solid Queue
- **Smart Processing**: Only processes images larger than 2MB
- **Quality Optimization**: Progressive quality reduction for smaller variants

### 3. CloudFront CDN Integration
- **Public S3 Access**: Images are publicly accessible for CDN
- **Cache Headers**: `public, max-age=31536000, immutable` for optimal caching
- **Direct URL Routing**: Custom Rails routes for CloudFront URLs

### 4. Performance Optimizations
- **Lazy Loading**: Background variant generation
- **Optimized Display**: Uses appropriate variant sizes in views
- **CDN Delivery**: Fast global content delivery via CloudFront

## AWS S3 Bucket Configuration

### 1. Create S3 Bucket
```bash
aws s3 mb s3://bizblasts-production-images
```

### 2. Configure Bucket Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::bizblasts-production-images/*"
    }
  ]
}
```

### 3. Configure CORS
```json
[
  {
    "AllowedHeaders": ["*"],
    "AllowedMethods": ["GET", "PUT", "POST"],
    "AllowedOrigins": ["https://bizblasts.com", "https://*.bizblasts.com"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }
]
```

## CloudFront CDN Setup (Optional)

### 1. Create CloudFront Distribution
- **Origin Domain**: your-s3-bucket.s3.amazonaws.com
- **Origin Path**: Leave empty
- **Viewer Protocol Policy**: Redirect HTTP to HTTPS
- **Allowed HTTP Methods**: GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE
- **Cache Behavior**: Cache based on selected request headers: None

### 2. Cache Behaviors
- **TTL Settings**: 
  - Default TTL: 86400 (1 day)
  - Maximum TTL: 31536000 (1 year)
- **Forward Headers**: None (for better caching)

## Code Changes Summary

### Models Updated
- `app/models/product.rb`: 15MB validation, variants, background processing
- `app/models/service.rb`: 15MB validation, variants, background processing

### Jobs Added
- `app/jobs/process_image_job.rb`: Background image variant generation

### Configuration Updated
- `config/puma.rb`: Timeout and content length settings
- `config/application.rb`: Image processing configuration
- `config/storage.yml`: S3 and CloudFront configuration
- `config/routes.rb`: CloudFront URL routing

### Views Updated
- Client-side validation in product and service forms
- Optimized image display using variants
- Enhanced file upload UI with size/format feedback

### Tests Updated
- Increased file size limits in model specs
- Added ProcessImageJob tests
- Updated supported formats in validations

## Deployment Checklist

1. ✅ Set environment variables in production
2. ✅ Create and configure S3 bucket
3. ✅ Set up CloudFront distribution (optional)
4. ✅ Test file uploads with large images
5. ✅ Verify background job processing
6. ✅ Check image variant generation
7. ✅ Confirm CDN delivery (if using CloudFront)

## Monitoring & Troubleshooting

### Check Background Jobs
```ruby
# Rails console
Solid::Queue::Job.where(job_class: 'ProcessImageJob').order(created_at: :desc).limit(10)
```

### Check Image Variants
```ruby
# Rails console
product = Product.first
product.images.first.variant(:medium).processed?
```

### S3 Storage Usage
```bash
aws s3 ls s3://bizblasts-production-images --recursive --human-readable --summarize
```

## Cost Optimization Tips

1. **Lifecycle Policies**: Set up S3 lifecycle rules for old variants
2. **Compression**: Images are automatically optimized by ImageMagick
3. **CDN Caching**: CloudFront reduces S3 requests significantly
4. **Smart Processing**: Only large images generate variants

## Security Notes

- S3 bucket has public read access for CDN functionality
- IAM user should have minimal required permissions
- CloudFront provides additional security layer
- File type validation prevents malicious uploads 
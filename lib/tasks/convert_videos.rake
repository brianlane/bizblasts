# frozen_string_literal: true

namespace :videos do
  desc "Convert existing .mov videos to MP4 for web compatibility"
  task convert_mov: :environment do
    puts "Finding businesses with .mov gallery videos..."

    businesses_with_mov = Business.joins(gallery_video_attachment: :blob)
                                   .where(active_storage_blobs: { content_type: 'video/quicktime' })

    count = businesses_with_mov.count
    puts "Found #{count} business(es) with .mov videos"

    if count == 0
      puts "No .mov videos to convert."
      exit
    end

    unless VideoConversionService.ffmpeg_available?
      puts "ERROR: ffmpeg is not installed. Please install it first:"
      puts "  macOS: brew install ffmpeg"
      puts "  Ubuntu: sudo apt-get install ffmpeg"
      exit 1
    end

    converted = 0
    failed = 0

    businesses_with_mov.find_each do |business|
      print "Converting video for #{business.name} (ID: #{business.id})... "

      if VideoConversionService.convert!(business)
        puts "✓ Done"
        converted += 1
      else
        puts "✗ Failed"
        failed += 1
      end
    end

    puts "\n=== Summary ==="
    puts "Converted: #{converted}"
    puts "Failed: #{failed}"
  end

  desc "Check video formats for all businesses"
  task check_formats: :environment do
    puts "Checking video formats...\n\n"

    Business.joins(gallery_video_attachment: :blob).find_each do |business|
      blob = business.gallery_video.blob
      needs_conversion = VideoConversionService.needs_conversion?(blob)
      status = needs_conversion ? "⚠️  NEEDS CONVERSION" : "✓ OK"

      puts "#{business.name} (ID: #{business.id})"
      puts "  File: #{blob.filename}"
      puts "  Type: #{blob.content_type}"
      puts "  Status: #{status}"
      puts ""
    end
  end
end


#!/usr/bin/env ruby
# frozen_string_literal: true

require 'rbconfig'

module PlaceIdExtraction
  # BrowserPathResolver finds a usable Chrome/Chromium executable for Cuprite
  class BrowserPathResolver
    ENV_KEYS = %w[
      CUPRITE_BROWSER_PATH
      BROWSER_PATH
      GOOGLE_CHROME_SHIM
      CHROME_PATH
      PLAYWRIGHT_CHROMIUM_PATH
    ].freeze

    PROJECT_PATHS = [
      Rails.root.join('vendor', 'chrome', 'chrome-linux64', 'chrome').to_s,
      Rails.root.join('vendor', 'chrome-linux64', 'chrome').to_s,
      Rails.root.join('vendor', 'chromium', 'chrome-linux64', 'chrome').to_s
    ].freeze

    LINUX_PATHS = %w[
      /opt/render/project/src/vendor/chrome/chrome-linux64/chrome
      /usr/bin/google-chrome
      /usr/bin/google-chrome-stable
      /usr/bin/chromium
      /usr/bin/chromium-browser
      /usr/local/bin/google-chrome
      /snap/bin/chromium
    ].freeze

    MAC_PATHS = [
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '/Applications/Chromium.app/Contents/MacOS/Chromium',
      '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
      '/opt/homebrew/bin/chromium',
      '/opt/homebrew/bin/google-chrome'
    ].freeze

    WINDOWS_PATHS = [
      'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
      'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
      'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe'
    ].freeze

    CHROME_BASENAMES = %w[
      chrome
      google-chrome
      google-chrome-stable
      chromium
      chromium-browser
      msedge
      msedge-headless
    ].freeze

    class << self
      def resolve
        path_from_env || path_from_project || path_from_system || path_from_path_env
      end

      private

      def path_from_env
        ENV_KEYS.each do |key|
          value = ENV[key]
          return value if valid_path?(value)
        end
        nil
      end

      def path_from_project
        PROJECT_PATHS.find { |candidate| valid_path?(candidate) }
      end

      def path_from_system
        candidate_paths.each do |candidate|
          return candidate if valid_path?(candidate)
        end
        nil
      end

      def path_from_path_env
        path_env = ENV['PATH']
        return nil if path_env.nil? || path_env.empty?

        path_env.split(File::PATH_SEPARATOR).each do |directory|
          CHROME_BASENAMES.each do |basename|
            candidate = File.join(directory, basename)
            return candidate if valid_path?(candidate)
          end
        end
        nil
      end

      def candidate_paths
        host_os = RbConfig::CONFIG['host_os']

        case host_os
        when /darwin/i
          MAC_PATHS
        when /mswin|mingw|cygwin/i
          WINDOWS_PATHS
        else
          LINUX_PATHS
        end
      end

      def valid_path?(path)
        path && !path.empty? && File.exist?(normalize_path(path))
      end

      def normalize_path(path)
        return path unless windows_path?(path)

        path.tr('\\', '/')
      end

      def windows_path?(path)
        path.include?('\\')
      end
    end
  end
end


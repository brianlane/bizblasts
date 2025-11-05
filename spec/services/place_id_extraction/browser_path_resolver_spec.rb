# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlaceIdExtraction::BrowserPathResolver do
  around do |example|
    original_env = ENV.to_hash
    example.run
  ensure
    ENV.replace(original_env)
  end

  describe '.resolve' do
    # Most tests need to prevent finding system Chrome
    # Platform-specific tests override these stubs as needed
    let(:stub_all_paths) { true }

    before do
      # Clear all browser-related environment variables
      described_class::ENV_KEYS.each { |key| ENV.delete(key) }
      ENV['PATH'] = '' # Clear PATH to prevent finding system browsers

      # Stub all path constants to prevent finding system Chrome (can be overridden per test)
      if stub_all_paths
        stub_const('PlaceIdExtraction::BrowserPathResolver::PROJECT_PATHS', [])
        stub_const('PlaceIdExtraction::BrowserPathResolver::MAC_PATHS', [])
        stub_const('PlaceIdExtraction::BrowserPathResolver::LINUX_PATHS', [])
        stub_const('PlaceIdExtraction::BrowserPathResolver::WINDOWS_PATHS', [])
        stub_const('PlaceIdExtraction::BrowserPathResolver::CHROME_BASENAMES', [])
      end
    end

    it 'returns path from CUPRITE_BROWSER_PATH when file exists' do
      tempfile = Tempfile.new('chrome')
      tempfile.close
      ENV['CUPRITE_BROWSER_PATH'] = tempfile.path

      expect(described_class.resolve).to eq(tempfile.path)
    ensure
      tempfile.unlink if tempfile
    end

    it 'returns vendor chrome path when present' do
      Dir.mktmpdir do |dir|
        # Create the vendor path
        candidate_path = File.join(dir, 'vendor', 'chrome', 'chrome-linux64', 'chrome')
        FileUtils.mkdir_p(File.dirname(candidate_path))
        FileUtils.touch(candidate_path)

        # Stub the PROJECT_PATHS to return our test path
        stub_const('PlaceIdExtraction::BrowserPathResolver::PROJECT_PATHS', [candidate_path])

        expect(described_class.resolve).to eq(candidate_path)
      end
    end

    it 'returns nil when no paths are available' do
      # Stub all path resolution methods to return nil
      allow(described_class).to receive(:path_from_env).and_return(nil)
      allow(described_class).to receive(:path_from_project).and_return(nil)
      allow(described_class).to receive(:path_from_system).and_return(nil)
      allow(described_class).to receive(:path_from_path_env).and_return(nil)

      expect(described_class.resolve).to be_nil
    end

    it 'checks multiple environment variables in priority order' do
      tempfile1 = Tempfile.new('chrome1')
      tempfile2 = Tempfile.new('chrome2')
      tempfile1.close
      tempfile2.close

      # Set lower priority env var first
      ENV['BROWSER_PATH'] = tempfile2.path
      # Set higher priority env var (CUPRITE_BROWSER_PATH should take precedence)
      ENV['CUPRITE_BROWSER_PATH'] = tempfile1.path

      # Should return the higher priority one
      expect(described_class.resolve).to eq(tempfile1.path)
    ensure
      tempfile1.unlink if tempfile1
      tempfile2.unlink if tempfile2
    end

    it 'skips environment variables with empty string values' do
      tempfile = Tempfile.new('chrome')
      tempfile.close

      ENV['CUPRITE_BROWSER_PATH'] = ''
      ENV['BROWSER_PATH'] = tempfile.path

      expect(described_class.resolve).to eq(tempfile.path)
    ensure
      tempfile.unlink if tempfile
    end

    it 'finds browser in PATH environment variable' do
      Dir.mktmpdir do |dir|
        chrome_path = File.join(dir, 'google-chrome')
        FileUtils.touch(chrome_path)
        FileUtils.chmod(0755, chrome_path)

        ENV['PATH'] = dir
        # Stub CHROME_BASENAMES to include the test browser name
        stub_const('PlaceIdExtraction::BrowserPathResolver::CHROME_BASENAMES', ['google-chrome'])

        expect(described_class.resolve).to eq(chrome_path)
      end
    end

    context 'edge cases' do
      it 'handles nil environment variable values' do
        ENV['CUPRITE_BROWSER_PATH'] = nil

        expect { described_class.resolve }.not_to raise_error
      end

      it 'handles paths with spaces' do
        Dir.mktmpdir do |dir|
          subdir = File.join(dir, 'Program Files', 'Chrome')
          FileUtils.mkdir_p(subdir)
          chrome_path = File.join(subdir, 'chrome')
          FileUtils.touch(chrome_path)

          ENV['CUPRITE_BROWSER_PATH'] = chrome_path

          expect(described_class.resolve).to eq(chrome_path)
        end
      end

      it 'handles Windows-style backslash paths' do
        # Create a temp file to represent the Windows path
        tempfile = Tempfile.new('chrome.exe')
        tempfile.close

        # Convert to Windows-style path with backslashes
        windows_path = tempfile.path.gsub('/', '\\')

        ENV['CUPRITE_BROWSER_PATH'] = windows_path

        result = described_class.resolve
        expect(result).to eq(windows_path)
      ensure
        tempfile.unlink if tempfile
      end

      it 'returns nil when PATH env var is empty' do
        # PATH is already cleared in the before block
        # Just verify it returns nil
        expect(described_class.resolve).to be_nil
      end

      it 'handles PATH with multiple colons/semicolons' do
        Dir.mktmpdir do |dir|
          chrome_path = File.join(dir, 'chromium')
          FileUtils.touch(chrome_path)

          # Add empty entries in PATH (::)
          ENV['PATH'] = "#{File::PATH_SEPARATOR}#{File::PATH_SEPARATOR}#{dir}#{File::PATH_SEPARATOR}"
          # Stub CHROME_BASENAMES to include the test browser name
          stub_const('PlaceIdExtraction::BrowserPathResolver::CHROME_BASENAMES', ['chromium'])

          expect(described_class.resolve).to eq(chrome_path)
        end
      end
    end

    context 'platform-specific paths' do
      # Don't stub path constants for these tests - they need to check the actual constants
      let(:stub_all_paths) { false }

      it 'checks macOS paths on darwin platform' do
        allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('darwin21.6.0')

        # The resolver will check macOS-specific paths
        resolver_paths = described_class.send(:candidate_paths)

        expect(resolver_paths).to include('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
        expect(resolver_paths).not_to include('/usr/bin/google-chrome')
      end

      it 'checks Linux paths on linux platform' do
        allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('linux-gnu')

        resolver_paths = described_class.send(:candidate_paths)

        expect(resolver_paths).to include('/usr/bin/google-chrome')
        expect(resolver_paths).not_to include('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
      end

      it 'checks Windows paths on windows platform' do
        allow(RbConfig::CONFIG).to receive(:[]).with('host_os').and_return('mswin64')

        resolver_paths = described_class.send(:candidate_paths)

        expect(resolver_paths).to include('C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe')
      end
    end
  end
end


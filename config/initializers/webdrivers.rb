# Configure webdrivers to use a specific ChromeDriver version 
# This is needed when running tests with non-standard Chrome versions

if defined?(Webdrivers::Chromedriver)
  # Using a stable version of ChromeDriver (known to work with Chrome version ~123-125)
  # Change this version if needed for compatibility with your installed Chrome
  Webdrivers::Chromedriver.required_version = '123.0.6312.58'
end 
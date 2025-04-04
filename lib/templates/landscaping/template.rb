module Templates
  module Landscaping
    class Template
      def self.default_template
        {
          name: "Landscaping Business Template",
          sections: ["header", "services", "projects", "testimonials", "contact"],
          color_scheme: "green",
          layout: "nature"
        }
      end
      
      def self.available_components
        ["header", "hero", "services", "projects", "gallery", "testimonials", "team", "pricing", "process", "before-after", "faq", "contact", "footer"]
      end
    end
  end
end

module Templates
  module General
    class Template
      def self.default_template
        {
          name: "General Business Template",
          sections: ["header", "about", "services", "testimonials", "contact"],
          color_scheme: "neutral",
          layout: "standard"
        }
      end
      
      def self.available_components
        ["header", "hero", "about", "services", "gallery", "testimonials", "team", "pricing", "faq", "contact", "footer"]
      end
    end
  end
end

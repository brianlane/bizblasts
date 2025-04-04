module Templates
  module PoolService
    class Template
      def self.default_template
        {
          name: "Pool Service Business Template",
          sections: ["header", "services", "maintenance-plans", "testimonials", "contact"],
          color_scheme: "blue",
          layout: "water"
        }
      end
      
      def self.available_components
        ["header", "hero", "services", "maintenance-plans", "gallery", "testimonials", "team", "pricing", "process", "seasonal-tips", "faq", "contact", "footer"]
      end
    end
  end
end

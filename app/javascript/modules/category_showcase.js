// BizBlasts Category Showcase Logic

const businessExamples = {
  Services: [
    "Hair Salons", "Massage Therapy", "Pet Grooming", "Auto Repair", "HVAC Services",
    "Plumbing", "Landscaping", "Pool Services", "Cleaning Services", "Tutoring",
    "Personal Training", "Photography", "Web Design", "Consulting", "Accounting",
    "Legal Services", "Dental Care", "Veterinary", "Handyman Service", "Painting",
    "Roofing", "Carpet Cleaning", "Pest Control", "Beauty Spa", "Moving Services",
    "Catering", "DJ Services", "Event Planning", "Tax Preparation", "IT Support"
  ],
  Experiences: [
    "Yoga Classes", "Escape Rooms", "Wine Tasting", "Cooking Classes", "Art Studios",
    "Dance Studios", "Music Lessons", "Adventure Tours", "Boat Charters", "Helicopter Tours",
    "Food Tours", "Ghost Tours", "Museums", "Aquariums", "Theme Parks",
    "Zip Lines", "Paintball", "Laser Tag", "Bowling Alleys", "Mini Golf",
    "Go-Kart Racing", "Arcades", "Comedy Clubs", "Theater Shows", "Concerts",
    "Festivals", "Workshops", "Seminars", "Retreats", "Spa Days"
  ],
  Products: [
    "Boutiques", "Jewelry Stores", "Electronics", "Bookstores", "Art Galleries",
    "Craft Stores", "Antique Shops", "Toy Stores", "Sports Equipment", "Outdoor Gear",
    "Home Decor", "Furniture Stores", "Bakeries", "Coffee Shops", "Wine Shops",
    "Specialty Foods", "Cosmetics", "Perfume Shops", "Pet Supplies", "Plant Nurseries",
    "Garden Centers", "Hardware Stores", "Music Stores", "Gift Shops", "Souvenir Shops",
    "Thrift Stores", "Clothing", "Local Artisans", "Handmade Goods", "Farmers Markets"
  ]
};

document.addEventListener('DOMContentLoaded', () => {
  const categoryTiles = document.querySelectorAll('.category-tile');

  categoryTiles.forEach(tile => {
    const examplesGridContainer = tile.querySelector('.examples-grid-container');
    const overlay = tile.querySelector('.overlay');
    const category = tile.dataset.category;
    const examples = businessExamples[category];

    tile.addEventListener('mouseenter', () => {
      // Show overlay
      overlay.classList.remove('hidden');
      overlay.classList.add('opacity-0', 'backdrop-blur-sm', 'bg-opacity-70'); // Initial state for transition
      // TODO: Add specific overlay background color based on category
      if (category === 'Services') {
        overlay.classList.add('bg-green-700');
      } else if (category === 'Experiences') {
        overlay.classList.add('bg-blue-700');
      } else if (category === 'Products') {
        overlay.classList.add('bg-orange-700');
      }
      
      // Animate overlay
      requestAnimationFrame(() => {
        overlay.classList.remove('opacity-0');
        overlay.classList.add('opacity-100');
      });

      // Tile lift and scale
      tile.classList.add('transform', 'scale-105', '-translate-y-2', 'shadow-2xl', 'z-20');
      tile.classList.remove('z-0');


      // Populate and show examples grid
      populateExamples(examplesGridContainer, examples, category);
      examplesGridContainer.classList.remove('hidden');
      examplesGridContainer.classList.add('z-30'); // Ensure grid is above overlay backdrop
    });

    tile.addEventListener('mouseleave', () => {
      // Hide overlay
      overlay.classList.add('opacity-0');
      overlay.classList.remove('opacity-100');
      setTimeout(() => {
        overlay.classList.add('hidden');
        overlay.classList.remove('backdrop-blur-sm', 'bg-opacity-70');
         if (category === 'Services') {
            overlay.classList.remove('bg-green-700');
        } else if (category === 'Experiences') {
            overlay.classList.remove('bg-blue-700');
        } else if (category === 'Products') {
            overlay.classList.remove('bg-orange-700');
        }
      }, 300); // Match transition duration

      // Revert tile transform
      tile.classList.remove('transform', 'scale-105', '-translate-y-2', 'shadow-2xl', 'z-20');
      tile.classList.add('z-0');

      // Hide and clear examples grid
      examplesGridContainer.classList.add('hidden');
      examplesGridContainer.innerHTML = ''; // Clear content
      examplesGridContainer.classList.remove('z-30');
    });
  });
});

async function populateExamples(container, examples, categoryName) {
  container.innerHTML = ''; // Clear previous examples
  const grid = document.createElement('div');
  // Added 'relative' to the grid for absolute positioning of example items if needed for complex animations
  grid.className = 'grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4 p-4 relative';
  
  // Add a title for the category within the modal
  const categoryTitle = document.createElement('h4');
  categoryTitle.className = 'col-span-full text-2xl font-bold text-white mb-4 text-center';
  categoryTitle.textContent = categoryName; // Use the passed category name
  grid.appendChild(categoryTitle);

  for (let i = 0; i < examples.length; i++) {
    const example = examples[i];
    const item = document.createElement('div');
    item.className = 'example-item p-3 rounded-md text-sm text-white opacity-0 transform translate-y-2 transition-all duration-300 ease-out';
    // Set initial style for staggered animation
    item.style.transitionDelay = `${i * 50}ms`;

    // Check if business industry exists
    try {
      const response = await fetch(`/check_business_industry?industry=${encodeURIComponent(example)}`);
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      const data = await response.json();
      
      if (data.exists) {
        item.classList.add('bg-white', 'bg-opacity-20', 'hover:bg-opacity-30', 'cursor-pointer', 'example-item-interactive');
        item.textContent = `${example} (Explore)`; // Indicate interactivity
        item.addEventListener('click', () => {
          // Placeholder for click action, e.g., redirect to a search page
          // window.location.href = `/search?industry=${encodeURIComponent(example)}`;
          console.log(`Clicked on existing industry: ${example}`);
        });
      } else {
        item.classList.add('bg-black', 'bg-opacity-10', 'cursor-default');
        item.textContent = example;
      }
    } catch (error) {
      console.error('Error checking industry:', error);
      item.classList.add('bg-black', 'bg-opacity-10', 'cursor-default');
      item.textContent = example; // Fallback if API fails
    }
    
    grid.appendChild(item);

    // Trigger animation
    requestAnimationFrame(() => {
      item.classList.remove('opacity-0', 'translate-y-2');
      item.classList.add('opacity-100', 'translate-y-0');
    });
  }
  container.appendChild(grid);
} 
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

// Cache for industry existence status
const industryExistenceCache = {};
let precachingDone = false;

// Function to pre-cache industry existence
async function preCacheIndustryExistence() {
  const allExamples = new Set();
  Object.values(businessExamples).forEach(list => list.forEach(example => allExamples.add(example)));

  const promises = [];
  allExamples.forEach(example => {
    promises.push(
      fetch(`/check_business_industry?industry=${encodeURIComponent(example)}`)
        .then(response => {
          if (!response.ok) throw new Error(`HTTP error for ${example}! status: ${response.status}`);
          return response.json();
        })
        .then(data => {
          industryExistenceCache[example] = data.exists;
        })
        .catch(error => {
          console.error('Error pre-caching industry:', example, error);
          industryExistenceCache[example] = false; // Default to false on error
        })
    );
  });

  await Promise.all(promises);
  precachingDone = true;
  console.log('Industry existence pre-caching complete.', industryExistenceCache);
}

document.addEventListener('DOMContentLoaded', () => {
  preCacheIndustryExistence(); // Start pre-caching on page load

  const categoryTiles = document.querySelectorAll('.category-tile');

  categoryTiles.forEach(tile => {
    const examplesGridContainer = tile.querySelector('.examples-grid-container');
    const overlay = tile.querySelector('.overlay');
    const categoryName = tile.dataset.category;
    const examples = businessExamples[categoryName];

    let overlayColorClass = '';
    let interactiveItemColorClass = '';

    if (categoryName === 'Services') {
      overlayColorClass = 'bg-green-700';
      interactiveItemColorClass = 'bg-green-500 bg-opacity-40 hover:bg-green-400 hover:bg-opacity-50';
    } else if (categoryName === 'Experiences') {
      overlayColorClass = 'bg-blue-700';
      interactiveItemColorClass = 'bg-blue-500 bg-opacity-40 hover:bg-blue-400 hover:bg-opacity-50';
    } else if (categoryName === 'Products') {
      overlayColorClass = 'bg-orange-700';
      interactiveItemColorClass = 'bg-orange-500 bg-opacity-40 hover:bg-orange-400 hover:bg-opacity-50';
    }

    tile.addEventListener('mouseenter', () => {
      overlay.classList.remove('hidden');
      overlay.classList.add('opacity-0', 'backdrop-blur-sm', 'bg-opacity-70', overlayColorClass);
      
      requestAnimationFrame(() => {
        overlay.classList.remove('opacity-0');
        overlay.classList.add('opacity-100');
      });

      tile.classList.add('transform', 'scale-105', '-translate-y-2', 'shadow-2xl', 'z-20');
      tile.classList.remove('z-0');

      populateExamples(examplesGridContainer, examples, categoryName, interactiveItemColorClass);
      examplesGridContainer.classList.remove('hidden');
      examplesGridContainer.classList.add('z-30');
    });

    tile.addEventListener('mouseleave', () => {
      overlay.classList.add('opacity-0');
      overlay.classList.remove('opacity-100');
      setTimeout(() => {
        overlay.classList.add('hidden');
        overlay.classList.remove('backdrop-blur-sm', 'bg-opacity-70', overlayColorClass);
      }, 300);

      tile.classList.remove('transform', 'scale-105', '-translate-y-2', 'shadow-2xl', 'z-20');
      tile.classList.add('z-0');

      examplesGridContainer.classList.add('hidden');
      examplesGridContainer.innerHTML = '';
      examplesGridContainer.classList.remove('z-30');
    });
  });
});

function populateExamples(container, examples, categoryName, interactiveItemColorClass) {
  container.innerHTML = '';
  const grid = document.createElement('div');
  grid.className = 'grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4 p-4 relative';
  
  const categoryTitle = document.createElement('h4');
  categoryTitle.className = 'col-span-full text-2xl font-bold text-white mb-4 text-center';
  categoryTitle.textContent = categoryName;
  grid.appendChild(categoryTitle);

  if (!precachingDone) {
    const loadingMessage = document.createElement('p');
    loadingMessage.className = 'col-span-full text-white text-center';
    loadingMessage.textContent = 'Loading industry data...';
    grid.appendChild(loadingMessage);
    // Optionally, you could implement a retry or a more robust loading indicator here
    // For now, it will just show the message if data isn't ready.
  }

  for (let i = 0; i < examples.length; i++) {
    const example = examples[i];
    const item = document.createElement('div');
    item.className = 'example-item p-3 rounded-md text-sm text-white opacity-0 transform translate-y-2 transition-all duration-300 ease-out';
    item.style.transitionDelay = `${i * 50}ms`;

    const exists = industryExistenceCache[example]; // Use cache

    if (exists === undefined && precachingDone) {
        // Data should have been precached but wasn't found (e.g. new example added dynamically and not in initial precache)
        // Or an error occurred during precaching for this specific example.
        console.warn(`Cache miss or error for: ${example}. Defaulting to non-interactive.`);
         item.classList.add('bg-black', 'bg-opacity-10', 'cursor-default');
         item.textContent = example;
    } else if (exists) {
      item.classList.add(...interactiveItemColorClass.split(' '), 'cursor-pointer', 'example-item-interactive');
      item.textContent = `${example} (Explore)`;
      item.addEventListener('click', () => {
        // window.location.href = `/search?industry=${encodeURIComponent(example)}`;
        console.log(`Clicked on existing industry: ${example}`);
      });
    } else {
      item.classList.add('bg-black', 'bg-opacity-10', 'cursor-default');
      item.textContent = example;
    }
    
    grid.appendChild(item);

    requestAnimationFrame(() => {
      item.classList.remove('opacity-0', 'translate-y-2');
      item.classList.add('opacity-100', 'translate-y-0');
    });
  }
  container.appendChild(grid);
} 
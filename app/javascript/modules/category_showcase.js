// BizBlasts Category Showcase Logic

// const businessExamples = { /* Original hardcoded examples removed */ };

document.addEventListener('DOMContentLoaded', () => {
  const showcaseDataElement = document.getElementById('showcase-data');
  let businessExamples = {};

  if (showcaseDataElement) {
    try {
      businessExamples = JSON.parse(showcaseDataElement.textContent);
    } catch (e) {
      console.error('Error parsing showcase data:', e);
      // Fallback to empty or default examples if parsing fails
      businessExamples = {
        Services: [],
        Experiences: [],
        Products: []
      };
    }
  } else {
    console.warn('Showcase data element not found. Using empty examples.');
    businessExamples = {
      Services: [],
      Experiences: [],
      Products: []
    };
  }

  const categoryTiles = document.querySelectorAll('.category-tile');

  categoryTiles.forEach(tile => {
    const examplesGridContainer = tile.querySelector('.examples-grid-container');
    const overlay = tile.querySelector('.overlay');
    const categoryName = tile.dataset.category;
    const examples = businessExamples[categoryName] || []; // Ensure examples is an array

    // Use brand colors for all tiles - secondary overlay, primary items for contrast
    let overlayColorClass = 'bg-secondary';
    let interactiveItemColorClass = 'bg-primary bg-opacity-80 hover:bg-primary hover:bg-opacity-100';

    tile.overlayTimeoutId = null;

    tile.addEventListener('mouseenter', () => {
      if (tile.overlayTimeoutId) {
        clearTimeout(tile.overlayTimeoutId);
        tile.overlayTimeoutId = null;
      }
      overlay.classList.remove('hidden');
      overlay.classList.add('backdrop-blur-sm', 'bg-opacity-50', overlayColorClass);
      overlay.classList.remove('opacity-100'); 
      overlay.classList.add('opacity-0');    
      
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
      if (tile.overlayTimeoutId) {
        clearTimeout(tile.overlayTimeoutId);
      }
      overlay.classList.remove('opacity-100');
      overlay.classList.add('opacity-0');
      
      tile.overlayTimeoutId = setTimeout(() => {
        overlay.classList.add('hidden');
        overlay.classList.remove('backdrop-blur-sm', 'bg-opacity-50', overlayColorClass);
        overlay.classList.remove('opacity-0', 'opacity-100'); 
        tile.overlayTimeoutId = null; 
      }, 300); 

      tile.classList.remove('transform', 'scale-105', '-translate-y-2', 'shadow-2xl', 'z-20');
      tile.classList.add('z-0');

      examplesGridContainer.classList.add('hidden');
      examplesGridContainer.innerHTML = ''; 
      examplesGridContainer.classList.remove('z-30');
    });
  });
});

function populateExamples(container, examples, categoryName, itemBackgroundColorClass) {
  container.innerHTML = ''; // Clear the main container

  // Create and append the title directly to the main container
  const categoryTitle = document.createElement('h4');
  categoryTitle.className = 'w-full text-2xl font-bold text-white mb-4 text-center'; 
  categoryTitle.textContent = categoryName;
  container.appendChild(categoryTitle); // Append title first

  // Create a new div that will be the flex container for the example items
  const itemsContainer = document.createElement('div');
  itemsContainer.className = 'w-full flex flex-wrap justify-center gap-x-2 gap-y-2 relative';

  if (!examples || examples.length === 0) { 
    const noExamplesMessage = document.createElement('p');
    noExamplesMessage.className = 'w-full text-white text-center text-sm'; // w-full for consistency
    itemsContainer.appendChild(noExamplesMessage);
    container.appendChild(itemsContainer); // Append the items container (with message) to main container
    return; 
  }

  for (let i = 0; i < examples.length; i++) {
    const example = examples[i];
    const item = document.createElement('div');
    item.className = 'example-item p-2 text-xs leading-normal rounded-md text-white opacity-0 transform translate-y-2 transition-all duration-300 ease-out';
    item.style.transitionDelay = `${i * 50}ms`;
    item.setAttribute('title', example); 

    item.classList.add(...itemBackgroundColorClass.split(' '), 'cursor-pointer');
    item.textContent = example; 

    item.addEventListener('click', () => {
      
      fetch(`/check_business_industry?industry=${encodeURIComponent(example)}`)
        .then(response => {
          if (!response.ok) {
            throw new Error(`HTTP error for ${example}! status: ${response.status}`);
          }
          return response.json();
        })
        .then(data => {
          if (data.exists === true) { 
            window.location.href = `/businesses?industry=${encodeURIComponent(example)}`;
          } else if (data.exists === false) { 
            window.location.href = '/businesses'; 
          } else {
            console.warn(`Branch: data.exists is neither true nor false for ${example}. Received:`, data.exists, 'Navigating to /businesses as a fallback.'); 
            window.location.href = '/businesses';
          }
        })
        .catch(error => {
          console.error('Error checking industry existence:', example, error);
          window.location.href = '/businesses';
        });
    });
    
    itemsContainer.appendChild(item); // Append item to the new itemsContainer

    requestAnimationFrame(() => {
      item.classList.remove('opacity-0', 'translate-y-2');
      item.classList.add('opacity-100', 'translate-y-0');
    });
  }
  container.appendChild(itemsContainer); // Append the itemsContainer (with items) to main container
} 
document.addEventListener('DOMContentLoaded', function() {
  const websiteHoverTrigger = document.getElementById('website-hover-trigger');
  
  if (!websiteHoverTrigger) return;
  
  let popup = null;
  let showTimeout = null;
  let hideTimeout = null;
  
  function createPopup() {
    if (popup) return popup;
    
    popup = document.createElement('div');
    popup.className = 'futuristic-popup';
    
    const link = document.createElement('a');
    link.href = '/docs/business-start-guide#subdomain-explanation';
    link.className = 'futuristic-popup-content';
    
    const icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    icon.setAttribute('class', 'futuristic-popup-icon');
    icon.setAttribute('fill', 'none');
    icon.setAttribute('stroke', 'currentColor');
    icon.setAttribute('viewBox', '0 0 24 24');
    
    const iconPath = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    iconPath.setAttribute('stroke-linecap', 'round');
    iconPath.setAttribute('stroke-linejoin', 'round');
    iconPath.setAttribute('stroke-width', '2');
    iconPath.setAttribute('d', 'M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1');
    
    icon.appendChild(iconPath);
    
    const text = document.createElement('span');
    text.className = 'futuristic-popup-text';
    text.textContent = 'Learn more here!';
    
    link.appendChild(icon);
    link.appendChild(text);
    popup.appendChild(link);
    
    websiteHoverTrigger.appendChild(popup);
    
    return popup;
  }
  
  function showPopup() {
    clearTimeout(hideTimeout);
    clearTimeout(showTimeout);
    
    showTimeout = setTimeout(() => {
      const popupElement = createPopup();
      popupElement.classList.add('show');
    }, 200); // Small delay for better UX
  }
  
  function hidePopup() {
    clearTimeout(showTimeout);
    clearTimeout(hideTimeout);
    
    hideTimeout = setTimeout(() => {
      if (popup) {
        popup.classList.remove('show');
      }
    }, 100); // Quick hide
  }
  
  // Mouse events for the trigger
  websiteHoverTrigger.addEventListener('mouseenter', showPopup);
  websiteHoverTrigger.addEventListener('mouseleave', hidePopup);
  
  // Keep popup visible when hovering over it
  websiteHoverTrigger.addEventListener('mouseover', function(e) {
    if (e.target.closest('.futuristic-popup')) {
      clearTimeout(hideTimeout);
    }
  });
  
  // Hide popup when mouse leaves the popup area
  websiteHoverTrigger.addEventListener('mouseleave', function(e) {
    if (!websiteHoverTrigger.contains(e.relatedTarget)) {
      hidePopup();
    }
  });
  
  // Touch support for mobile
  websiteHoverTrigger.addEventListener('touchstart', function(e) {
    e.preventDefault();
    if (popup && popup.classList.contains('show')) {
      hidePopup();
    } else {
      showPopup();
    }
  });
  
  // Close popup when clicking outside on mobile
  document.addEventListener('touchstart', function(e) {
    if (popup && popup.classList.contains('show') && !websiteHoverTrigger.contains(e.target)) {
      hidePopup();
    }
  });
}); 
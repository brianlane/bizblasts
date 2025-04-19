# # config/initializers/active_admin_delete_fix.rb
# ActiveAdmin.setup do |config|
#   # Add JavaScript directly to the head
#   config.head = <<-HTML.html_safe
#     <script>
#       document.addEventListener('DOMContentLoaded', function() {
#         // For all delete links: Find and replace their behavior
#         function fixDeleteLinks() {
#           document.querySelectorAll('a.delete_link, a[data-method="delete"]').forEach(function(link) {
#             // Skip links we've already processed
#             if (link.dataset.fixedDelete) return;
            
#             // Mark as processed
#             link.dataset.fixedDelete = 'true';
            
#             // Replace the click handler
#             link.addEventListener('click', function(event) {
#               event.preventDefault();
#               event.stopPropagation();
              
#               var url = this.getAttribute('href');
#               var confirmMessage = this.getAttribute('data-confirm') || 'Are you sure?';
              
#               if (confirm(confirmMessage)) {
#                 var form = document.createElement('form');
#                 form.method = 'POST';
#                 form.action = url;
#                 form.style.display = 'none';
                
#                 var methodInput = document.createElement('input');
#                 methodInput.type = 'hidden';
#                 methodInput.name = '_method';
#                 methodInput.value = 'delete';
#                 form.appendChild(methodInput);
                
#                 var csrfToken = document.querySelector('meta[name="csrf-token"]').content;
#                 var tokenInput = document.createElement('input');
#                 tokenInput.type = 'hidden';
#                 tokenInput.name = 'authenticity_token';
#                 tokenInput.value = csrfToken;
#                 form.appendChild(tokenInput);
                
#                 document.body.appendChild(form);
#                 form.submit();
#               }
              
#               return false;
#             });
            
#             // Remove data-method to prevent Rails UJS from interfering
#             link.removeAttribute('data-method');
#           });
#         }
        
#         // Run once on page load
#         fixDeleteLinks();
        
#         // Also run after AJAX requests complete (for dynamically added content)
#         document.addEventListener('ajax:complete', fixDeleteLinks);
        
#         // Monitor for DOM changes to catch any newly added delete links
#         var observer = new MutationObserver(fixDeleteLinks);
#         observer.observe(document.body, { childList: true, subtree: true });
#       });
#     </script>
#   HTML
  
#   # Keep the original footer if there is one
#   if config.footer.present?
#     original_footer = config.footer
#     config.footer = original_footer
#   end
# end

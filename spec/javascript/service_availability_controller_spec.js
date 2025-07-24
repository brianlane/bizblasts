// Unit tests for ServiceAvailabilityController addTimeSlotToContainer
// Ensures correct parameter naming for nested and standalone forms

import ServiceAvailabilityController from '../../app/javascript/controllers/service_availability_controller.js';

// Helper to create a DOM structure for the controller
const createControllerDom = ({ nested = true } = {}) => {
  document.body.innerHTML = `
    <form id="testForm">
      ${nested ? '<input type="hidden" name="service[name]" value="Test Service">' : ''}
      <div id="controller" data-controller="service-availability">
        <div id="monday-slots"></div>
      </div>
    </form>`;

  const element = document.getElementById('controller');
  const slotsContainer = document.getElementById('monday-slots');
  return { element, slotsContainer };
}

// Suppress console logs from the controller during tests
beforeEach(() => {
  jest.spyOn(console, 'log').mockImplementation(() => {});
});

afterEach(() => {
  jest.restoreAllMocks();
  document.body.innerHTML = '';
});

describe('ServiceAvailabilityController#addTimeSlotToContainer', () => {
  it('uses nested parameter names when the form includes service[ ... ] fields', () => {
    const { element, slotsContainer } = createControllerDom({ nested: true });

    const controller = new ServiceAvailabilityController();
    controller.element = element;

    controller.addTimeSlotToContainer('monday', slotsContainer);

    const hiddenInput = slotsContainer.querySelector('input[type="hidden"]');
    expect(hiddenInput).not.toBeNull();
    expect(hiddenInput.name).toMatch(/^service\[availability\]\[monday\]\[\d+\]\[id\]$/);
  });

  it('uses standalone parameter names when the form lacks service[ ... ] fields', () => {
    const { element, slotsContainer } = createControllerDom({ nested: false });

    const controller = new ServiceAvailabilityController();
    controller.element = element;

    controller.addTimeSlotToContainer('monday', slotsContainer);

    const hiddenInput = slotsContainer.querySelector('input[type="hidden"]');
    expect(hiddenInput).not.toBeNull();
    expect(hiddenInput.name).toMatch(/^availability\[monday\]\[\d+\]\[id\]$/);
  });
}); 
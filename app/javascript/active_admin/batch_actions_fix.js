/**
 * Batch Actions Select Fix
 *
 * ActiveAdmin renders batch actions as a dropdown that depends on jQuery.
 * Our test suite (and desired UX) expect a native <select> element with a
 * companion “Go” button inside `.batch_actions_selector`. This script
 * transforms the default markup into that shape and wires up submission so
 * batch actions behave exactly once per trigger.
 */

const BATCH_FORM_ID = "collection_selection";
const SELECT_ID = "batch_action";
const CHECKBOX_SELECTOR = 'input[name="collection_selection[]"]';
const TOGGLE_SELECTOR = 'input[name="collection_selection_toggle_all"]';

function closestBatchForm() {
  return document.getElementById(BATCH_FORM_ID);
}

function hasSelectedRows() {
  return document.querySelectorAll(`${CHECKBOX_SELECTOR}:checked`).length > 0;
}

function hideLegacyDropdown(container) {
  const dropdownButton = container.querySelector(".dropdown_menu_button");
  if (dropdownButton) dropdownButton.style.display = "none";

  const dropdownWrapper = container.querySelector(".dropdown_menu_list_wrapper");
  if (dropdownWrapper) dropdownWrapper.style.display = "none";
}

function buildSelect(container) {
  const select = document.createElement("select");
  select.id = SELECT_ID;
  select.name = SELECT_ID;
  select.setAttribute("form", BATCH_FORM_ID);
  select.classList.add("batch-actions-select");

  const placeholder = document.createElement("option");
  placeholder.value = "";
  placeholder.textContent = "Select batch action";
  placeholder.disabled = true;
  placeholder.selected = true;
  select.appendChild(placeholder);

  container.querySelectorAll("a.batch_action").forEach((link) => {
    const value = link.dataset.action || "";
    if (!value) return;

    const option = document.createElement("option");
    option.value = value;
    option.textContent = link.textContent.trim();

    if (link.dataset.confirm) option.dataset.confirm = link.dataset.confirm;
    if (link.dataset.inputs && link.dataset.inputs !== "null") {
      option.dataset.inputs = link.dataset.inputs;
    }

    select.appendChild(option);
  });

  return select;
}

function buildGoButton() {
  const button = document.createElement("button");
  button.type = "submit";
  button.textContent = "Go";
  button.classList.add("batch-actions-go");
  button.setAttribute("form", BATCH_FORM_ID);
  button.disabled = true;
  return button;
}

function detachPreviousControls(container) {
  const oldSelect = container.querySelector(`select#${SELECT_ID}`);
  if (oldSelect) oldSelect.remove();

  const oldButton = container.querySelector("button.batch-actions-go");
  if (oldButton) oldButton.remove();
}

function renameHiddenBatchInput(form) {
  const hiddenInput = form.querySelector(`#${SELECT_ID}`);
  if (!hiddenInput || hiddenInput.dataset.rebound) return hiddenInput;

  hiddenInput.id = `${SELECT_ID}_hidden`;
  hiddenInput.name = `_hidden_${SELECT_ID}`;
  hiddenInput.disabled = true;
  hiddenInput.dataset.rebound = "true";
  return hiddenInput;
}

function attachCheckboxListeners(updateFn) {
  const checkboxes = document.querySelectorAll(`${CHECKBOX_SELECTOR}, ${TOGGLE_SELECTOR}`);
  checkboxes.forEach((checkbox) => {
    checkbox.removeEventListener("change", updateFn);
    checkbox.addEventListener("change", updateFn);
  });
}

function applySelectBehaviour(container) {
  if (container.dataset.batchSelectInitialized === "true") return;

  const form = closestBatchForm();
  if (!form) return;

  detachPreviousControls(container);
  hideLegacyDropdown(container);

  const hiddenInput = renameHiddenBatchInput(form);
  const select = buildSelect(container);
  const goButton = buildGoButton();

  if (select.options.length <= 1) {
    return;
  }

  container.appendChild(select);
  container.appendChild(goButton);

  const updateButtonState = () => {
    const hasAction = select.value !== "";
    goButton.disabled = !(hasAction && hasSelectedRows());
  };

  const checkboxChangeHandler = () => window.requestAnimationFrame(updateButtonState);

  select.addEventListener("change", updateButtonState);
  attachCheckboxListeners(checkboxChangeHandler);
  updateButtonState();

  if (!form.dataset.batchSelectSubmitBound) {
    form.addEventListener("submit", (event) => {
      const selectedOption = select.selectedOptions[0];

      if (!selectedOption || !selectedOption.value) {
        event.preventDefault();
        alert("Please choose a batch action before continuing.");
        return;
      }

      if (!hasSelectedRows()) {
        event.preventDefault();
        alert("Please select at least one item.");
        return;
      }

      const confirmMessage = selectedOption.dataset.confirm;
      if (confirmMessage && !window.confirm(confirmMessage)) {
        event.preventDefault();
        return;
      }

      if (hiddenInput) {
        hiddenInput.disabled = false;
        hiddenInput.name = SELECT_ID;
        hiddenInput.value = selectedOption.value;
      }

      const batchInputs = form.querySelector("#batch_action_inputs");
      if (batchInputs) {
        const extraInputs = selectedOption.dataset.inputs;
        if (extraInputs) {
          batchInputs.value = extraInputs;
          batchInputs.removeAttribute("disabled");
        } else {
          batchInputs.value = "";
          batchInputs.setAttribute("disabled", "disabled");
        }
      }
    });

    form.dataset.batchSelectSubmitBound = "true";
  }

  container.dataset.batchSelectInitialized = "true";
}

function resetBeforeCache() {
  document.querySelectorAll(".batch_actions_selector").forEach((container) => {
    delete container.dataset.batchSelectInitialized;

    const select = container.querySelector(`select#${SELECT_ID}`);
    if (select) select.remove();

    const goButton = container.querySelector("button.batch-actions-go");
    if (goButton) goButton.remove();
  });
}

function initializeBatchActionsSelect() {
  document.querySelectorAll(".batch_actions_selector").forEach((container) => {
    applySelectBehaviour(container);
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initializeBatchActionsSelect);
} else {
  initializeBatchActionsSelect();
}

document.addEventListener("turbo:load", initializeBatchActionsSelect);
document.addEventListener("turbo:before-cache", resetBeforeCache);

export default initializeBatchActionsSelect;

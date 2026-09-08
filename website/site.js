const tabs = [...document.querySelectorAll('[role="tab"]')];
const tablist = document.querySelector('[role="tablist"]');

function selectClient(id) {
  for (const tab of tabs) {
    const selected = tab.getAttribute('aria-controls') === id;
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
    const panel = document.getElementById(tab.getAttribute('aria-controls'));
    panel.hidden = !selected;
  }
}

for (const tab of tabs) {
  const id = tab.getAttribute('aria-controls');
  const panel = document.getElementById(id);
  panel.setAttribute('role', 'tabpanel');
  panel.setAttribute('aria-labelledby', tab.id);
  panel.tabIndex = 0;
  tab.addEventListener('click', () => selectClient(id));
  tab.addEventListener('keydown', event => {
    const index = tabs.indexOf(tab);
    const next = {ArrowRight: (index + 1) % tabs.length, ArrowLeft: (index - 1 + tabs.length) % tabs.length,
      Home: 0, End: tabs.length - 1}[event.key];
    if (next === undefined) return;
    event.preventDefault();
    selectClient(tabs[next].getAttribute('aria-controls'));
    tabs[next].focus({preventScroll: true});
  });
}
selectClient(location.hash === '#claude' ? 'claude' : 'codex');
tablist.hidden = false;
window.addEventListener('hashchange', () => {
  const id = location.hash.slice(1);
  if (id === 'codex' || id === 'claude') selectClient(id);
});

const status = document.getElementById('copy-status');
for (const button of document.querySelectorAll('[data-copy]')) {
  button.hidden = false;
  const label = button.textContent;
  let reset;
  button.addEventListener('click', async () => {
    clearTimeout(reset);
    button.disabled = true;
    button.textContent = 'Copying…';
    try {
      await navigator.clipboard.writeText(document.getElementById(button.dataset.copy).textContent.trim());
      button.dataset.state = 'copied';
      button.textContent = 'Copied ✓';
      status.textContent = 'Copied to clipboard.';
    } catch {
      button.dataset.state = 'error';
      button.textContent = 'Select text';
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(document.getElementById(button.dataset.copy));
      selection.removeAllRanges();
      selection.addRange(range);
      status.textContent = 'Clipboard unavailable. The text is selected; copy it manually.';
    } finally {
      button.disabled = false;
      reset = setTimeout(() => {
        button.textContent = label;
        delete button.dataset.state;
      }, 2500);
    }
  });
}

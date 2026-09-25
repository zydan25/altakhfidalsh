(() => {
  const STORAGE_KEY = "altakhfidalsh:admin-nav-open";
  const sidebar = document.getElementById("adminSidebar");
  const overlay = document.getElementById("drawerOverlay");
  const menuButton = document.getElementById("menuButton");
  const sections = [...document.querySelectorAll(".nav-section")];

  const readState = () => {
    try {
      return JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
    } catch {
      return {};
    }
  };

  const writeState = (state) => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  };

  const state = readState();

  sections.forEach((section, index) => {
    const button = section.querySelector(".nav-section-button");
    const children = section.querySelector(".nav-children");
    const key = String(index);
    const activeParent = section.classList.contains("is-active-parent");
    const open = Object.prototype.hasOwnProperty.call(state, key) ? !!state[key] : activeParent;

    section.classList.toggle("is-open", open);
    button.setAttribute("aria-expanded", String(open));
    children.hidden = !open;

    button.addEventListener("click", () => {
      const nextOpen = !section.classList.contains("is-open");
      section.classList.toggle("is-open", nextOpen);
      button.setAttribute("aria-expanded", String(nextOpen));
      children.hidden = !nextOpen;
      state[key] = nextOpen;
      writeState(state);
    });
  });

  const setDrawer = (open) => {
    sidebar.classList.toggle("is-open", open);
    overlay.hidden = !open;
    menuButton.setAttribute("aria-expanded", String(open));
    document.body.style.overflow = open ? "hidden" : "";
  };

  menuButton?.addEventListener("click", () => setDrawer(!sidebar.classList.contains("is-open")));
  document.getElementById("mobileMoreButton")?.addEventListener("click", () => setDrawer(true));
  overlay?.addEventListener("click", () => setDrawer(false));
  sidebar?.querySelectorAll("a").forEach((link) => link.addEventListener("click", () => setDrawer(false)));

  window.addEventListener("resize", () => {
    if (window.innerWidth >= 900) setDrawer(false);
  });
})();


// Reusable admin modals, slug generation and color helpers.
(() => {
  const slugify = (value) => {
    const map = {
      ا:'a',أ:'a',إ:'i',آ:'a',ء:'a',ؤ:'w',ئ:'y',ب:'b',ت:'t',ث:'th',ج:'j',ح:'h',خ:'kh',د:'d',ذ:'dh',ر:'r',ز:'z',س:'s',ش:'sh',ص:'s',ض:'d',ط:'t',ظ:'z',ع:'a',غ:'gh',ف:'f',ق:'q',ك:'k',ل:'l',م:'m',ن:'n',ه:'h',و:'w',ي:'y',ى:'a',ة:'h',ﻻ:'la'
    };
    const transliterated = String(value || '').toLowerCase().split('').map(ch => map[ch] || ch).join('');
    return transliterated.normalize('NFKD').replace(/[\u064B-\u065F\u0670]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 180);
  };

  document.querySelectorAll('[data-open-modal]').forEach((button) => {
    button.addEventListener('click', () => {
      const modal = document.querySelector('[data-modal="' + button.dataset.openModal + '"]');
      if (!modal) return;
      modal.hidden = false;
      document.body.classList.add('modal-open');
      modal.querySelector('input:not([type="hidden"]), textarea, select')?.focus();
    });
  });
  document.querySelectorAll('[data-close-modal]').forEach((button) => {
    button.addEventListener('click', () => {
      const modal = button.closest('.admin-modal');
      if (!modal) return;
      modal.hidden = true;
      document.body.classList.remove('modal-open');
    });
  });
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    document.querySelectorAll('.admin-modal:not([hidden])').forEach((modal) => {
      modal.hidden = true;
      document.body.classList.remove('modal-open');
    });
  });

  document.querySelectorAll('[data-slug-form]').forEach((form) => {
    const slug = form.querySelector('input[name="slug"]');
    const source = form.querySelector('input[name="name"], input[name="title"], input[name="code"]');
    if (!slug || !source) return;
    let touched = false;
    slug.addEventListener('input', () => { touched = slug.value.trim().length > 0; });
    source.addEventListener('input', () => {
      if (!touched || !slug.value.trim()) slug.value = slugify(source.value);
    });
    form.addEventListener('submit', () => {
      if (!slug.value.trim()) slug.value = slugify(source.value);
    });
  });

  document.querySelectorAll('[data-color-text]').forEach((textInput) => {
    const colorInput = textInput.closest('.color-input-row')?.querySelector('input[type="color"]');
    if (!colorInput) return;
    colorInput.addEventListener('input', () => { textInput.value = colorInput.value; });
    textInput.addEventListener('input', () => {
      const value = textInput.value.trim();
      if (/^#[0-9a-fA-F]{6}$/.test(value)) colorInput.value = value;
    });
  });
})();

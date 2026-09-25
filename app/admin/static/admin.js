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

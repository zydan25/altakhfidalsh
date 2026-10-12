(() => {
  "use strict";
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const norm = (value) => String(value || "").trim().toLocaleLowerCase("ar").replace(/\s+/g, " ");
  const number = (value) => { const n = Number(value); return Number.isFinite(n) ? n : 0; };
  const setHidden = (element, hidden) => { if (element) element.hidden = Boolean(hidden); };

  function initProductFilters() {
    const toolbar = $("[data-product-filters]"), grid = $("#adminProductCards");
    if (!toolbar || !grid) return;
    const cards = $$(".admin-product-card[data-product-id]", grid);
    cards.forEach((card, index) => { card.dataset.defaultOrder = String(index); });
    const textSearch = $("#productTextSearch"), trigger = $("#productCategoryTrigger");
    const menu = $("#productCategoryMenu"), catSearch = $("#productCategorySearch");
    const catSearchButton = $("#productCategorySearchButton"), label = $("#selectedProductCategory");
    const choices = $$(".product-category-choice", toolbar), sortSelect = $("#productSortOrder");
    const count = $("#productResultsCount"), clear = $("#clearProductFilters"), empty = $("#productFilterEmpty");
    let selectedCategory = "";

    function filterChoices() {
      const term = norm(catSearch && catSearch.value);
      choices.forEach((choice) => choice.classList.toggle("water-filter-hidden",
        Boolean(term) && !norm(choice.dataset.categorySearch || choice.textContent).includes(term)));
    }
    function apply() {
      const term = norm(textSearch && textSearch.value), sort = sortSelect ? sortSelect.value : "default";
      const matched = cards.filter((card) => {
        const textMatch = !term || norm(card.dataset.productSearch).includes(term);
        const ids = (card.dataset.categoryIds || "").split(",").filter(Boolean);
        const show = textMatch && (!selectedCategory || ids.includes(selectedCategory));
        card.classList.toggle("water-filter-hidden", !show);
        return show;
      });
      matched.sort((a,b) => {
        if (sort === "stock-asc") return number(a.dataset.stock)-number(b.dataset.stock) || number(a.dataset.defaultOrder)-number(b.dataset.defaultOrder);
        if (sort === "orders-desc") return number(b.dataset.orders)-number(a.dataset.orders) || number(a.dataset.defaultOrder)-number(b.dataset.defaultOrder);
        if (sort === "price-asc") return number(a.dataset.price)-number(b.dataset.price) || number(a.dataset.defaultOrder)-number(b.dataset.defaultOrder);
        return number(a.dataset.defaultOrder)-number(b.dataset.defaultOrder);
      });
      matched.forEach((card) => grid.appendChild(card));
      if (count) count.textContent = "عرض " + matched.length + " من " + cards.length + " منتج";
      setHidden(empty, matched.length > 0 || cards.length === 0);
    }
    trigger && trigger.addEventListener("click", (event) => {
      event.stopPropagation();
      const open = menu && menu.hidden;
      setHidden(menu, !open);
      trigger.setAttribute("aria-expanded", String(Boolean(open)));
      if (open && catSearch) catSearch.focus();
    });
    choices.forEach((choice) => choice.addEventListener("click", () => {
      selectedCategory = choice.dataset.productCategoryId || "";
      if (label) label.textContent = choice.dataset.productCategoryName || choice.textContent.trim();
      choices.forEach((item) => item.classList.toggle("is-selected", item === choice));
      setHidden(menu, true);
      trigger && trigger.setAttribute("aria-expanded", "false");
      apply();
    }));
    catSearch && catSearch.addEventListener("input", filterChoices);
    catSearchButton && catSearchButton.addEventListener("click", filterChoices);
    textSearch && textSearch.addEventListener("input", apply);
    sortSelect && sortSelect.addEventListener("change", apply);
    clear && clear.addEventListener("click", () => {
      if (textSearch) textSearch.value = "";
      if (catSearch) catSearch.value = "";
      if (sortSelect) sortSelect.value = "default";
      const all = choices.find((choice) => !choice.dataset.productCategoryId);
      if (all) all.click();
      filterChoices(); apply();
    });
    document.addEventListener("click", (event) => {
      if (menu && !toolbar.contains(event.target)) {
        setHidden(menu, true);
        trigger && trigger.setAttribute("aria-expanded", "false");
      }
    });
    catSearch && catSearch.addEventListener("keydown", (event) => {
      if (event.key === "Enter") { event.preventDefault(); filterChoices(); }
      if (event.key === "Escape") { setHidden(menu, true); trigger && trigger.setAttribute("aria-expanded", "false"); }
    });
    apply();
  }

  function initCustomerFilters() {
    const toolbar = $("[data-customer-controls]"), grid = $("#adminCustomerCards");
    if (!toolbar || !grid) return;
    const cards = $$(".entity-card[data-customer-id]", grid);
    cards.forEach((card, i) => { card.dataset.defaultOrder = String(i); });
    const search = $("#customerSearch"), sortSelect = $("#customerSort"), count = $("#customerResultsCount");
    const empty = $("#customerFilterEmpty"), clear = $("#clearCustomerFilters"), tabs = $$("[data-customer-group]", toolbar);
    let group = "all";
    function apply() {
      const term = norm(search && search.value);
      const matched = cards.filter((card) => {
        const textMatch = !term || norm(card.dataset.customerSearch).includes(term);
        const complete = card.dataset.onboarding === "complete", invites = number(card.dataset.invites);
        const groupMatch = group === "all" || (group === "complete" && complete) ||
          (group === "incomplete" && !complete) || (group === "invited" && invites > 0);
        card.classList.toggle("water-filter-hidden", !(textMatch && groupMatch));
        return textMatch && groupMatch;
      });
      const sort = sortSelect ? sortSelect.value : "newest";
      matched.sort((a,b) => {
        if (sort === "oldest") return number(a.dataset.customerId)-number(b.dataset.customerId);
        if (sort === "invites") return number(b.dataset.invites)-number(a.dataset.invites) || number(a.dataset.defaultOrder)-number(b.dataset.defaultOrder);
        if (sort === "name") return norm(a.dataset.customerSearch).localeCompare(norm(b.dataset.customerSearch), "ar");
        return number(b.dataset.customerId)-number(a.dataset.customerId);
      });
      matched.forEach((card) => grid.appendChild(card));
      if (count) count.textContent = "عرض " + matched.length + " من " + cards.length + " عميل";
      setHidden(empty, matched.length > 0 || cards.length === 0);
    }
    tabs.forEach((tab) => tab.addEventListener("click", () => {
      group = tab.dataset.customerGroup || "all";
      tabs.forEach((button) => button.classList.toggle("is-active", button === tab));
      apply();
    }));
    search && search.addEventListener("input", apply);
    sortSelect && sortSelect.addEventListener("change", apply);
    clear && clear.addEventListener("click", () => {
      if (search) search.value = "";
      if (sortSelect) sortSelect.value = "newest";
      group = "all";
      tabs.forEach((button) => button.classList.toggle("is-active", button.dataset.customerGroup === "all"));
      apply();
    });
    apply();
  }

  function initOrderFilters() {
    const toolbar = $("[data-order-controls]"), grid = $("#adminOrderCards");
    if (!toolbar || !grid) return;
    const cards = $$(".entity-card[data-order-id]", grid);
    cards.forEach((card, i) => { card.dataset.defaultOrder = String(i); });
    const search = $("#orderSearch"), payment = $("#orderPaymentFilter"), sortSelect = $("#orderSort");
    const count = $("#orderResultsCount"), empty = $("#orderFilterEmpty"), clear = $("#clearOrderFilters");
    const tabs = $$("[data-order-group]", toolbar); let group = "all";
    const newStatuses = new Set(["created", "awaiting_payment"]);
    const processing = new Set(["paid", "processing", "shipped", "in_transit", "intransit", "shiped"]);
    const completed = new Set(["delivered", "completed"]), cancelled = new Set(["cancelled", "canceled"]);
    function inGroup(status) {
      if (group === "new") return newStatuses.has(status);
      if (group === "processing") return processing.has(status);
      if (group === "completed") return completed.has(status);
      if (group === "cancelled") return cancelled.has(status);
      return true;
    }
    function apply() {
      const term = norm(search && search.value), paymentValue = norm(payment ? payment.value : "all");
      const matched = cards.filter((card) => {
        const textMatch = !term || norm(card.dataset.orderSearch).includes(term);
        const payMatch = paymentValue === "all" || norm(card.dataset.paymentStatus) === paymentValue;
        const show = textMatch && payMatch && inGroup(norm(card.dataset.orderStatus));
        card.classList.toggle("water-filter-hidden", !show);
        return show;
      });
      const sort = sortSelect ? sortSelect.value : "newest";
      matched.sort((a,b) => {
        if (sort === "oldest") return number(a.dataset.orderId)-number(b.dataset.orderId);
        if (sort === "total-desc") return number(b.dataset.orderTotal)-number(a.dataset.orderTotal);
        if (sort === "total-asc") return number(a.dataset.orderTotal)-number(b.dataset.orderTotal);
        return number(b.dataset.orderId)-number(a.dataset.orderId);
      });
      matched.forEach((card) => grid.appendChild(card));
      if (count) count.textContent = "عرض " + matched.length + " من " + cards.length + " طلب";
      setHidden(empty, matched.length > 0 || cards.length === 0);
    }
    tabs.forEach((tab) => tab.addEventListener("click", () => {
      group = tab.dataset.orderGroup || "all";
      tabs.forEach((button) => button.classList.toggle("is-active", button === tab));
      apply();
    }));
    search && search.addEventListener("input", apply);
    payment && payment.addEventListener("change", apply);
    sortSelect && sortSelect.addEventListener("change", apply);
    clear && clear.addEventListener("click", () => {
      if (search) search.value = "";
      if (payment) payment.value = "all";
      if (sortSelect) sortSelect.value = "newest";
      group = "all";
      tabs.forEach((button) => button.classList.toggle("is-active", button.dataset.orderGroup === "all"));
      apply();
    });
    apply();
  }

  function initBrandSearch() {
    const toolbar = $("[data-brand-controls]");
    if (!toolbar) return;
    const cards = $$("[data-brand-card]"), search = $("#brandSearch"), count = $("#brandResultsCount");
    const empty = $("#brandFilterEmpty"), clear = $("#clearBrandSearch");
    function apply() {
      const term = norm(search && search.value); let visible = 0;
      cards.forEach((card) => {
        const show = !term || norm(card.dataset.brandSearch).includes(term);
        card.classList.toggle("water-filter-hidden", !show);
        if (show) visible += 1;
      });
      if (count) count.textContent = "عرض " + visible + " من " + cards.length + " علامة";
      setHidden(empty, visible > 0 || cards.length === 0);
    }
    search && search.addEventListener("input", apply);
    clear && clear.addEventListener("click", () => { if (search) search.value = ""; apply(); });
    apply();
  }

  function initSettingsTabs() {
    const root = $(".page-content");
    if (!root || !$$(".module-header h2", root).some((heading) => heading.textContent.trim() === "الإعدادات")) return;
    const direct = Array.from(root.children);
    const headingText = (el) => norm($("h3", el) && $("h3", el).textContent);
    const findDirect = (selector, phrase) => direct.find((el) => el.matches(selector) && headingText(el).includes(norm(phrase)));
    const appearance = findDirect(".general-images-setting", "مظهر لوحة التحكم");
    const signature = direct.find((el) => el.classList.contains("developer-signature-setting"));
    const account = direct.find((el) => el.classList.contains("account-status-setting"));
    const productImages = findDirect(".general-images-setting", "إظهار الصور العامة");
    const contact = findDirect("section.panel", "بيانات التواصل والموقع");
    const splash = findDirect("section.panel", "مدة شاشة البداية");
    const advanced = direct.find((el) => el.classList.contains("two-panel"));
    const groups = [
      {label:"مظهر اللوحة", nodes:[appearance]},
      {label:"هوية التطبيق", nodes:[signature]},
      {label:"واجهة المتجر", nodes:[account, productImages, contact, splash]},
      {label:"الإعدادات المتقدمة", nodes:[advanced]}
    ].map((g) => ({label:g.label,nodes:g.nodes.filter(Boolean)})).filter((g) => g.nodes.length);
    const allNodes = groups.flatMap((g) => g.nodes);
    if (allNodes.length < 3) return;
    const marker = document.createComment("water-settings-tabs");
    root.insertBefore(marker, allNodes[0]);
    const layout = document.createElement("section"); layout.className = "water-tab-layout water-settings-tab-layout";
    const nav = document.createElement("div"); nav.className = "water-admin-tabs"; nav.setAttribute("role","tablist"); nav.setAttribute("aria-label","أقسام الإعدادات");
    const panes = document.createElement("div"); panes.className = "water-tab-panes";
    const buttons = [];
    groups.forEach((g,index) => {
      const button = document.createElement("button"); button.type = "button"; button.className = "water-admin-tab";
      button.setAttribute("role","tab"); button.setAttribute("aria-selected", index === 0 ? "true" : "false"); button.textContent = g.label;
      nav.appendChild(button); buttons.push(button);
      const pane = document.createElement("div"); pane.className = "water-tab-pane"; pane.setAttribute("role","tabpanel"); pane.hidden = index !== 0;
      g.nodes.forEach((node) => pane.appendChild(node)); panes.appendChild(pane);
      button.addEventListener("click", () => {
        buttons.forEach((b,i) => { const active = i === index; b.classList.toggle("is-active",active); b.setAttribute("aria-selected",String(active)); });
        $$(".water-tab-pane",panes).forEach((p,i) => { p.hidden = i !== index; });
      });
    });
    buttons[0] && buttons[0].classList.add("is-active");
    layout.append(nav,panes); root.insertBefore(layout,marker); marker.remove();
  }

  function initProductDetailTabs() {
    const page = $(".pds-page"); if (!page) return;
    const panels = $$(".pds-panel", page); if (panels.length < 2) return;
    const nav = document.createElement("div"); nav.className = "water-admin-tabs water-pds-tabs";
    nav.setAttribute("role","tablist"); nav.setAttribute("aria-label","أقسام إعدادات تفاصيل الصنف");
    const buttons = [];
    function activate(index) {
      buttons.forEach((button,i) => { const active = i === index; button.classList.toggle("is-active",active); button.setAttribute("aria-selected",String(active)); });
      panels.forEach((panel,i) => panel.classList.toggle("water-pds-hidden",i !== index));
    }
    panels.forEach((panel,index) => {
      const heading = $("h3",panel);
      const button = document.createElement("button"); button.type = "button"; button.className = "water-admin-tab";
      button.setAttribute("role","tab"); button.setAttribute("aria-selected",index === 0 ? "true":"false");
      button.textContent = heading ? heading.textContent.trim() : ("القسم " + (index + 1));
      button.addEventListener("click",() => activate(index)); nav.appendChild(button); buttons.push(button);
    });
    panels[0].parentNode.insertBefore(nav,panels[0]); activate(0);
  }

  function init() {
    if (!document.body.classList.contains("water-admin-theme")) return;
    initProductFilters(); initCustomerFilters(); initOrderFilters(); initBrandSearch();
    initSettingsTabs(); initProductDetailTabs();
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded",init,{once:true});
  else init();
})();

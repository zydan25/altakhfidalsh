(() => {
  const seedElement = document.getElementById("trendEditorSeed");
  const modal = document.querySelector('[data-modal="trendEditorModal"]');
  const form = document.getElementById("trendEditorForm");
  if (!seedElement || !modal || !form) return;

  const els = {
    title: document.getElementById("trendEditorTitle"),
    action: document.getElementById("trendEditorAction"),
    id: document.getElementById("trendEditorId"),
    hashtag: document.getElementById("trendHashtagSelect"),
    hashtagId: document.getElementById("trendHashtagId"),
    promo: document.getElementById("trendPromoText"),
    duration: document.getElementById("trendDurationDays"),
    sort: document.getElementById("trendSortOrder"),
    status: document.getElementById("trendStatus"),
    timerEnabled: document.getElementById("trendTimerEnabled"),
    timerValue: document.getElementById("trendTimerValue"),
    timerUnit: document.getElementById("trendTimerUnit"),
    overlayText: document.getElementById("trendOverlayText"),
    overlayTextColor: document.getElementById("trendOverlayTextColor"),
    overlayTextColorText: document.getElementById("trendOverlayTextColorText"),
    overlayBackgroundColor: document.getElementById("trendOverlayBackgroundColor"),
    overlayBackgroundColorText: document.getElementById("trendOverlayBackgroundColorText"),
    file: document.getElementById("trendBackgroundFile"),
    preview: document.getElementById("trendBackgroundPreview"),
    previewImage: document.getElementById("trendBackgroundImage"),
    count: document.getElementById("trendSelectedCount"),
    selected: document.getElementById("trendSelectedProducts"),
    empty: document.getElementById("trendProductEmpty"),
    search: document.getElementById("trendProductSearch"),
    candidates: document.getElementById("trendProductCandidates"),
    hiddenProducts: document.getElementById("trendProductInputs"),
    auto: document.getElementById("autoTrendProducts"),
    save: form.querySelector(".trend-save-button"),
  };

  let seeds = [];
  let products = [];
  let productMap = new Map();
  let selectedIds = new Set();
  let loadedHashtagId = null;
  let backgroundObjectUrl = null;

  try {
    seeds = JSON.parse(seedElement.textContent || "[]") || [];
  } catch (error) {
    seeds = [];
  }

  const notify = (message, type = "error") => {
    let box = modal.querySelector(".trend-editor-message");
    if (!box) {
      box = document.createElement("div");
      box.className = "trend-editor-message";
      form.prepend(box);
    }
    box.textContent = message;
    box.dataset.type = type;
    box.hidden = false;
  };

  const clearNotify = () => {
    const box = modal.querySelector(".trend-editor-message");
    if (box) box.hidden = true;
  };

  const syncColorPair = (colorInput, textInput) => {
    if (!colorInput || !textInput) return;
    colorInput.addEventListener("input", () => { textInput.value = colorInput.value.toUpperCase(); });
    textInput.addEventListener("input", () => {
      const value = textInput.value.trim();
      if (/^#[0-9a-fA-F]{6}$/.test(value)) colorInput.value = value;
    });
  };

  syncColorPair(els.overlayTextColor, els.overlayTextColorText);
  syncColorPair(els.overlayBackgroundColor, els.overlayBackgroundColorText);

  const openModal = () => {
    modal.hidden = false;
    document.body.classList.add("modal-open");
    requestAnimationFrame(() => {
      modal.querySelector("select, textarea, input")?.focus();
      modal.querySelector(".admin-modal-dialog")?.scrollTo({ top: 0, behavior: "instant" });
    });
  };

  const closeModal = () => {
    modal.hidden = true;
    document.body.classList.remove("modal-open");
    clearNotify();
  };

  const revokeBackgroundUrl = () => {
    if (backgroundObjectUrl) {
      URL.revokeObjectURL(backgroundObjectUrl);
      backgroundObjectUrl = null;
    }
  };

  const setBackgroundPreview = (url) => {
    if (!url) {
      els.preview.hidden = true;
      els.previewImage.removeAttribute("src");
      return;
    }
    els.previewImage.src = url;
    els.preview.hidden = false;
  };

  const resetBackgroundInput = () => {
    revokeBackgroundUrl();
    els.file.value = "";
  };

  const formatPrice = (value) => {
    const number = Number(value);
    return Number.isFinite(number) ? number.toLocaleString("ar-SA") : String(value || "—");
  };

  const productBrand = (product) => product?.brand?.name || "بدون علامة";
  const productImage = (product) => product?.image_url || "";

  const resetProducts = () => {
    products = [];
    productMap = new Map();
    selectedIds = new Set();
    loadedHashtagId = null;
    renderSelected();
    renderCandidates();
  };

  const syncHiddenProductInputs = () => {
    els.hiddenProducts.replaceChildren();
    [...selectedIds].forEach((id) => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = "product_ids";
      input.value = String(id);
      els.hiddenProducts.appendChild(input);
    });
  };

  const renderSelected = () => {
    els.selected.replaceChildren();
    const ordered = [...selectedIds];
    els.count.textContent = ordered.length + " من 3";
    els.count.dataset.valid = ordered.length === 3 ? "true" : "false";

    ordered.forEach((id, index) => {
      const product = productMap.get(id);
      if (!product) return;
      const card = document.createElement("article");
      card.className = "trend-selected-product";
      card.dataset.productId = String(id);
      card.innerHTML = `
        <div class="trend-selected-product-slot">${index + 1}</div>
        <div class="trend-selected-product-media">
          ${productImage(product)
            ? `<img src="${escapeHtml(productImage(product))}" alt="${escapeHtml(product.name || "منتج")}">`
            : '<span class="trend-product-placeholder">□</span>'}
        </div>
        <div class="trend-selected-product-copy">
          <strong>${escapeHtml(productBrand(product))}</strong>
          <span>${escapeHtml(product.name || "منتج")}</span>
          <small>${formatPrice(product.price)} ر.س</small>
        </div>
        <button class="trend-selected-remove" type="button" data-remove-product="${id}" aria-label="إزالة المنتج">×</button>
      `;
      els.selected.appendChild(card);
    });

    els.empty.hidden = ordered.length > 0;
    syncHiddenProductInputs();
  };

  const renderCandidates = () => {
    const needle = (els.search.value || "").trim().toLocaleLowerCase("ar");
    els.candidates.replaceChildren();

    const filtered = products.filter((product) => {
      if (!needle) return true;
      return [
        product.name,
        product.sku,
        product.slug,
        productBrand(product),
      ].some((value) => String(value || "").toLocaleLowerCase("ar").includes(needle));
    });

    if (!loadedHashtagId) {
      els.candidates.innerHTML = '<div class="trend-product-empty">اختر هاشتاجًا لعرض المنتجات المرتبطة به.</div>';
      return;
    }

    if (!filtered.length) {
      els.candidates.innerHTML = '<div class="trend-product-empty">لا توجد منتجات منشورة مرتبطة بهذا الهاشتاج.</div>';
      return;
    }

    filtered.forEach((product) => {
      const selected = selectedIds.has(product.id);
      const disabled = !selected && selectedIds.size >= 3;
      const button = document.createElement("button");
      button.type = "button";
      button.className = "trend-candidate-card" + (selected ? " is-selected" : "") + (disabled ? " is-disabled" : "");
      button.dataset.productId = String(product.id);
      button.disabled = disabled;
      button.innerHTML = `
        <span class="trend-candidate-check">${selected ? "✓" : ""}</span>
        <span class="trend-candidate-media">
          ${productImage(product)
            ? `<img src="${escapeHtml(productImage(product))}" alt="${escapeHtml(product.name || "منتج")}" loading="lazy">`
            : '<span class="trend-product-placeholder">□</span>'}
        </span>
        <span class="trend-candidate-copy">
          <strong>${escapeHtml(product.name || "منتج")}</strong>
          <small>${escapeHtml(productBrand(product))} · ${formatPrice(product.price)} ر.س</small>
          <small class="trend-candidate-sku" dir="ltr">${escapeHtml(product.sku || "")}</small>
        </span>
      `;
      els.candidates.appendChild(button);
    });
  };

  const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#039;",
  }[char]));

  const selectProduct = (rawId) => {
    const id = Number(rawId);
    if (!Number.isInteger(id)) return;
    if (selectedIds.has(id)) {
      selectedIds.delete(id);
    } else {
      if (selectedIds.size >= 3) {
        notify("يمكن اختيار 3 منتجات فقط لهذا المستطيل.");
        return;
      }
      if (!productMap.has(id)) return;
      selectedIds.add(id);
    }
    clearNotify();
    renderSelected();
    renderCandidates();
  };

  const loadProducts = async (hashtagId, preserveSelected = false) => {
    const id = Number(hashtagId);
    loadedHashtagId = Number.isInteger(id) ? id : null;
    if (!loadedHashtagId) {
      resetProducts();
      return;
    }

    if (!preserveSelected) {
      selectedIds = new Set();
    }

    els.candidates.innerHTML = '<div class="trend-product-empty trend-loading">جاري تحميل منتجات الهاشتاج...</div>';
    try {
      const response = await fetch(
        `/api/v1/catalog/reference/hashtag-products?hashtag_id=${encodeURIComponent(loadedHashtagId)}&limit=100`,
        { cache: "no-store", credentials: "same-origin", headers: { Accept: "application/json" } }
      );
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.detail || "تعذر تحميل منتجات الهاشتاج.");
      products = Array.isArray(payload.items) ? payload.items : [];
      productMap = new Map(products.map((product) => [Number(product.id), product]));

      if (preserveSelected) {
        const allowed = new Set(products.map((product) => Number(product.id)));
        selectedIds = new Set([...selectedIds].filter((id) => allowed.has(id)));
      }
      renderSelected();
      renderCandidates();
    } catch (error) {
      products = [];
      productMap = new Map();
      if (!preserveSelected) selectedIds = new Set();
      renderSelected();
      els.candidates.innerHTML = `<div class="trend-product-empty trend-error">${escapeHtml(error.message || "تعذر تحميل المنتجات.")}</div>`;
    }
  };

  const openCreate = () => {
    els.action.value = "create";
    els.id.value = "";
    els.title.textContent = "إضافة مستطيل الترند";
    els.hashtag.value = "";
    els.hashtagId.value = "";
    els.promo.value = "";
    els.duration.value = "8";
    els.sort.value = "0";
    els.status.value = "active";
    els.timerEnabled.checked = false;
    els.timerValue.value = "60";
    els.timerUnit.value = "seconds";
    els.overlayText.value = "";
    els.overlayTextColor.value = "#FFFFFF";
    els.overlayTextColorText.value = "#FFFFFF";
    els.overlayBackgroundColor.value = "#111827";
    els.overlayBackgroundColorText.value = "#111827";
    resetBackgroundInput();
    setBackgroundPreview("");
    els.search.value = "";
    resetProducts();
    clearNotify();
    openModal();
  };

  const openEdit = async (id) => {
    const trend = seeds.find((item) => Number(item.id) === Number(id));
    if (!trend) {
      notify("لم يتم العثور على بيانات الترند.");
      return;
    }

    els.action.value = "update";
    els.id.value = String(trend.id);
    els.title.textContent = "تعديل مستطيل الترند";
    els.hashtag.value = String(trend.hashtag_id || "");
    els.hashtagId.value = String(trend.hashtag_id || "");
    els.promo.value = trend.promo_text || "";
    els.duration.value = String(trend.duration_days || 8);
    els.sort.value = String(trend.sort_order || 0);
    els.status.value = trend.status === "active" ? "active" : "draft";
    els.timerEnabled.checked = Boolean(trend.timer_enabled);
    els.timerValue.value = String(trend.timer_value || 60);
    els.timerUnit.value = trend.timer_unit === "minutes" ? "minutes" : "seconds";
    els.overlayText.value = trend.overlay_text || "";
    els.overlayTextColor.value = trend.overlay_text_color || "#FFFFFF";
    els.overlayTextColorText.value = (trend.overlay_text_color || "#FFFFFF").toUpperCase();
    els.overlayBackgroundColor.value = trend.overlay_background_color || "#111827";
    els.overlayBackgroundColorText.value = (trend.overlay_background_color || "#111827").toUpperCase();
    resetBackgroundInput();
    setBackgroundPreview(trend.background_url || "");
    els.search.value = "";

    selectedIds = new Set(
      (trend.products || [])
        .map((item) => Number(item?.product?.id))
        .filter((value) => Number.isInteger(value))
    );
    products = (trend.products || []).map((item) => item.product).filter(Boolean);
    productMap = new Map(products.map((product) => [Number(product.id), product]));
    loadedHashtagId = Number(trend.hashtag_id || 0) || null;
    renderSelected();
    renderCandidates();
    clearNotify();
    openModal();
    await loadProducts(trend.hashtag_id, true);

    (trend.products || []).forEach((item) => {
      if (item?.product?.id) productMap.set(Number(item.product.id), item.product);
    });
    renderSelected();
    renderCandidates();
  };

  const autoLink = () => {
    if (!loadedHashtagId) {
      notify("اختر الهاشتاج أولًا.");
      return;
    }
    if (products.length < 3) {
      notify("لا يوجد 3 منتجات منشورة مرتبطة بهذا الهاشتاج.");
      return;
    }
    selectedIds = new Set(products.slice(0, 3).map((product) => Number(product.id)));
    clearNotify();
    renderSelected();
    renderCandidates();
  };

  els.hashtag.addEventListener("change", async () => {
    const value = els.hashtag.value;
    els.hashtagId.value = value;
    await loadProducts(value, false);
  });

  document.querySelectorAll("[data-trend-hashtag]").forEach((button) => {
    button.addEventListener("click", async () => {
      const value = button.dataset.trendHashtag;
      els.hashtag.value = value;
      els.hashtagId.value = value;
      document.querySelectorAll("[data-trend-hashtag]").forEach((item) => item.classList.toggle("is-active", item === button));
      await loadProducts(value, false);
    });
  });

  els.candidates.addEventListener("click", (event) => {
    const button = event.target.closest("[data-product-id]");
    if (!button) return;
    selectProduct(button.dataset.productId);
  });

  els.selected.addEventListener("click", (event) => {
    const button = event.target.closest("[data-remove-product]");
    if (!button) return;
    selectProduct(button.dataset.removeProduct);
  });

  els.search.addEventListener("input", renderCandidates);
  els.auto.addEventListener("click", autoLink);

  const syncTimerDisabled = () => {
    const disabled = !els.timerEnabled.checked;
    els.timerValue.disabled = disabled;
    els.timerUnit.disabled = disabled;
  };
  els.timerEnabled.addEventListener("change", syncTimerDisabled);
  syncTimerDisabled();

  els.file.addEventListener("change", () => {
    const file = els.file.files?.[0];
    revokeBackgroundUrl();
    if (!file) {
      setBackgroundPreview("");
      return;
    }
    if (!file.type.startsWith("image/")) {
      els.file.value = "";
      notify("يجب اختيار صورة.");
      setBackgroundPreview("");
      return;
    }
    backgroundObjectUrl = URL.createObjectURL(file);
    setBackgroundPreview(backgroundObjectUrl);
    clearNotify();
  });

  document.querySelectorAll("[data-trend-create]").forEach((button) => {
    button.addEventListener("click", openCreate);
  });

  document.querySelectorAll("[data-trend-edit]").forEach((button) => {
    button.addEventListener("click", () => openEdit(button.dataset.trendEdit));
  });

  document.querySelectorAll("[data-trend-close]").forEach((button) => {
    button.addEventListener("click", closeModal);
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !modal.hidden) closeModal();
  });

  form.addEventListener("submit", (event) => {
    els.hashtagId.value = els.hashtag.value;
    syncHiddenProductInputs();

    if (!els.hashtag.value) {
      event.preventDefault();
      notify("اختر الهاشتاج الرئيسي للترند.");
      els.hashtag.focus();
      return;
    }
    if (selectedIds.size !== 3) {
      event.preventDefault();
      notify("يجب اختيار 3 منتجات للترند بالضبط.");
      return;
    }
    if (els.action.value === "create" && !els.file.files?.[0]) {
      event.preventDefault();
      notify("صورة الخلفية مطلوبة عند إنشاء الترند.");
      return;
    }
    clearNotify();
    if (els.overlayTextColorText.value) els.overlayTextColor.value = els.overlayTextColorText.value;
    if (els.overlayBackgroundColorText.value) els.overlayBackgroundColor.value = els.overlayBackgroundColorText.value;
    if (els.save) {
      els.save.disabled = true;
      els.save.textContent = "جاري الحفظ...";
    }
  });

  els.hashtag.addEventListener("change", () => {
    document.querySelectorAll("[data-trend-hashtag]").forEach((button) => {
      button.classList.toggle("is-active", String(button.dataset.trendHashtag) === String(els.hashtag.value));
    });
  });

  renderSelected();
  renderCandidates();
})();

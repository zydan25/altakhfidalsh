(() => {
  const root = document.querySelector("[data-product-pro-editor]");
  if (!root) return;

  const productId = Number(root.dataset.productId || 0);
  const wizardSeed = document.getElementById("wizardReferenceSeed");
  let refs = {};
  try { refs = JSON.parse(wizardSeed?.textContent || "{}") || {}; } catch (error) { refs = {}; }

  let snapshot = null;
  let colorIds = new Set();
  let sizeIds = new Set();
  let sizeGuideIds = [];
  let selectedLocationId = null;
  let pickerType = null;
  let pickerWorking = new Set();
  let pendingImageColorId = null;
  let previewItem = null;
  const stockTimers = new Map();
  const stockRequests = new Map();

  const $ = (selector, scope = document) => scope.querySelector(selector);
  const $$ = (selector, scope = document) => [...scope.querySelectorAll(selector)];

  const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, char => ({
    "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#039;"
  }[char]));

  const notify = (message, type = "success") => {
    const box = $("#proWizardMessage");
    if (!box) return;
    box.textContent = message;
    box.className = "alert " + type;
    box.hidden = false;
    box.scrollIntoView({behavior:"smooth", block:"start"});
  };

  const requestJson = async (url, options = {}) => {
    const headers = options.body instanceof FormData
      ? {}
      : {"Content-Type":"application/json","Accept":"application/json"};
    const response = await fetch(url, {
      cache:"no-store",
      credentials:"same-origin",
      ...options,
      headers:{...headers,...(options.headers || {})}
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.detail || data.error || "تعذر تنفيذ العملية");
    return data;
  };

  const allColorRows = () => refs.colors || [];
  const allSizeRows = () => refs.sizes || [];
  const colors = () => allColorRows().filter(x => x && (x.is_active !== false || colorIds.has(Number(x.id))));
  const sizes = () => allSizeRows().filter(x => x && (x.is_active !== false || sizeIds.has(Number(x.id))));

  const colorById = id => allColorRows().find(x => Number(x.id) === Number(id));
  const sizeById = id => allSizeRows().find(x => Number(x.id) === Number(id));

  const activeVariants = () => (snapshot?.variants || []).filter(v => {
    if (v.is_active === false) return false;
    return v.status == null || v.status === "active";
  });

  const variantFor = (colorId, sizeId) => activeVariants().find(v =>
    Number(v.color_id) === Number(colorId) && Number(v.size_id) === Number(sizeId)
  );

  const stocksFor = variantId => (snapshot?.inventory || []).filter(row =>
    Number(row.variant_id) === Number(variantId)
  );

  const stockForLocation = variantId => stocksFor(variantId).find(row =>
    Number(row.location_id) === Number(selectedLocationId)
  ) || null;

  const patchStock = item => {
    if (!item) return;
    const old = (snapshot.inventory || []).find(row =>
      Number(row.variant_id) === Number(item.variant_id) &&
      Number(row.location_id) === Number(item.location_id)
    );
    const merged = {...(old || {}), ...item};
    snapshot.inventory = (snapshot.inventory || [])
      .filter(row => !(Number(row.variant_id) === Number(item.variant_id) && Number(row.location_id) === Number(item.location_id)))
      .concat(merged);
  };

  const syncLegacyWizard = async () => {
    try {
      if (typeof window.takhfidProductWizardReload === "function") {
        await window.takhfidProductWizardReload();
      }
    } catch (error) {}
  };

  const afterMutation = async ({reloadLegacy = true} = {}) => {
    if (reloadLegacy) await syncLegacyWizard();
    await refreshData();
  };

  const hydrateSelections = () => {
    const serverColors = (snapshot?.reference_colors || []).map(x => Number(x.id)).filter(Boolean);
    const serverSizes = (snapshot?.reference_sizes || []).map(x => Number(x.id)).filter(Boolean);

    if (!colorIds.size) {
      if (serverColors.length) colorIds = new Set(serverColors);
      else colorIds = new Set(activeVariants().map(v => Number(v.color_id)).filter(Boolean));
    }

    if (!sizeIds.size) {
      if (serverSizes.length) sizeIds = new Set(serverSizes);
      else sizeIds = new Set(activeVariants().map(v => Number(v.size_id)).filter(Boolean));
    }

    if (!sizeGuideIds.length) {
      const guideRows = (refs.size_guides || []).filter(x => x.selected);
      guideRows.sort((a,b) =>
        Number(a.sort_order ?? 999999) - Number(b.sort_order ?? 999999) ||
        String(a.name || "").localeCompare(String(b.name || ""), "ar")
      );
      sizeGuideIds = guideRows.map(x => Number(x.id)).filter(Boolean);
    }
  };

  const chooseInitialLocation = () => {
    const locations = snapshot?.locations || [];
    if (!locations.length) {
      selectedLocationId = null;
      return;
    }
    let stored = 0;
    try { stored = Number(localStorage.getItem("takhfid:product-stock-location:" + productId) || 0); } catch (error) {}
    const validStored = locations.some(x => Number(x.id) === stored) ? stored : null;
    const common = locations.map(location => ({
      id:Number(location.id),
      count:(snapshot.inventory || []).filter(row => Number(row.location_id) === Number(location.id)).length
    })).sort((a,b) => b.count - a.count)[0]?.id;
    if (!selectedLocationId || !locations.some(x => Number(x.id) === Number(selectedLocationId))) {
      selectedLocationId = validStored || common || Number(locations[0].id);
    }
  };

  const renderLocation = () => {
    chooseInitialLocation();
    const select = $("#proInventoryLocation");
    const locations = snapshot?.locations || [];
    if (!select) return;
    if (!locations.length) {
      select.innerHTML = '<option value="">لا يوجد مخزن — أضف موقعًا أدناه</option>';
      return;
    }
    select.innerHTML = locations.map(location =>
      '<option value="' + location.id + '"' +
      (Number(location.id) === Number(selectedLocationId) ? ' selected' : '') + '>' +
      escapeHtml(location.name) + ' · ' + escapeHtml(location.code || "") +
      '</option>'
    ).join("");
  };

  const renderSelectedChips = () => {
    const colorRoot = $("#proSelectedColors");
    const sizeRoot = $("#proSelectedSizes");

    if (colorRoot) {
      const rows = [...colorIds].map(colorById).filter(Boolean);
      colorRoot.innerHTML = rows.length
        ? rows.map(row =>
          '<span class="pro-selected-chip">' +
            '<span class="pro-swatch" style="background:' + escapeHtml(row.hex_code || "#e5e7eb") + '"></span>' +
            '<span>' + escapeHtml(row.name) + '</span>' +
            '<button type="button" data-remove-color="' + row.id + '" aria-label="إزالة اللون">×</button>' +
          '</span>'
        ).join("")
        : '<span class="muted" style="font-size:10px;padding-top:8px">أضف لونًا واحدًا على الأقل.</span>';
    }

    if (sizeRoot) {
      const rows = [...sizeIds].map(sizeById).filter(Boolean);
      sizeRoot.innerHTML = rows.length
        ? rows.map(row =>
          '<span class="pro-selected-chip">' +
            '<span class="pro-size-badge">' + escapeHtml(row.code || row.label) + '</span>' +
            '<span>' + escapeHtml(row.label) + '</span>' +
            '<button type="button" data-remove-size="' + row.id + '" aria-label="إزالة المقاس">×</button>' +
          '</span>'
        ).join("")
        : '<span class="muted" style="font-size:10px;padding-top:8px">أضف مقاسًا واحدًا على الأقل.</span>';
    }
  };

  const persistDimensions = async () => requestJson(
    "/api/v1/catalog/products/" + productId + "/reference-dimensions",
    {
      method:"POST",
      body:JSON.stringify({
        color_ids:[...colorIds].map(Number),
        size_ids:[...sizeIds].map(Number)
      })
    }
  );

  const generateMissingVariants = async () => {
    if (!colorIds.size || !sizeIds.size) return;
    await requestJson("/api/v1/catalog/products/" + productId + "/variants/generate", {
      method:"POST",
      body:JSON.stringify({
        color_ids:[...colorIds].map(Number),
        size_ids:[...sizeIds].map(Number)
      })
    });
  };

  const openPicker = type => {
    pickerType = type;
    const previousIds = new Set(type === "color" ? [...colorIds] : [...sizeIds]);
    pickerWorking = new Set(previousIds);
    const overlay = document.createElement("div");
    overlay.className = "pro-picker-backdrop";
    overlay.dataset.proPicker = "1";

    const selected = id => pickerWorking.has(Number(id));
    const rows = type === "color" ? colors() : sizes();
    const heading = type === "color" ? "ألوان المنتج" : "مقاسات المنتج";
    const hint = type === "color"
      ? "اختر لونًا من القائمة، أو أنشئ لونًا جديدًا من لوحة اللون أو HEX."
      : "اختر المقاسات التي تعتبر متاحة لهذا المنتج. بعد ذلك يمكنك إضافة كل مقاس إلى لون محدد فقط.";

    const colorMaker = type === "color"
      ? '<div class="pro-color-maker">' +
          '<div class="pro-color-maker-head"><div><strong>إنشاء لون جديد</strong><small>لوحة اللون أو اكتب قيمة HEX ثم احفظها.</small></div><span class="pro-color-maker-preview" data-pro-new-color-preview></span></div>' +
          '<div class="pro-color-maker-fields">' +
            '<input type="color" value="#111111" data-pro-new-color-picker aria-label="لوحة اختيار اللون">' +
            '<input type="text" value="#111111" maxlength="7" dir="ltr" data-pro-new-color-hex placeholder="#111111" inputmode="text">' +
            '<input type="text" value="" data-pro-new-color-name placeholder="اسم اللون">' +
            '<button type="button" class="pro-primary-btn" data-pro-create-color>إنشاء وإضافة</button>' +
          '</div>' +
        '</div>'
      : '';

    const allSizesSwitch = type === "size"
      ? '<label class="pro-all-size-switch"><input type="checkbox" data-pro-add-size-all><span><strong>إضافة المقاس الجديد إلى جميع الألوان</strong><small>عند التفعيل سيتم إنشاء المتغيرات الناقصة لكل لون. عند الإيقاف يبقى المقاس متاحًا في قائمة الإضافة الخاصة بكل لون فقط.</small></span></label>'
      : "";

    overlay.innerHTML =
      '<section class="pro-picker-sheet" role="dialog" aria-modal="true">' +
        '<div class="pro-picker-head"><div><span class="pro-sheet-eyebrow">' + (type === "color" ? "مرجع اللون" : "مرجع المقاس") + '</span><h3>' + heading + '</h3><p>' + hint + '</p></div><button class="pro-picker-close" type="button" data-pro-picker-close>×</button></div>' +
        colorMaker +
        '<div class="pro-picker-grid">' +
          (rows.length ? rows.map(row => {
            const active = selected(row.id);
            if (type === "color") {
              return '<button type="button" class="pro-picker-choice ' + (active ? 'is-selected' : '') + '" data-pro-picker-value="' + row.id + '">' +
                '<span class="pro-swatch" style="background:' + escapeHtml(row.hex_code || "#e5e7eb") + '"></span>' +
                '<strong>' + escapeHtml(row.name) + '</strong>' +
                (row.is_active === false ? '<small>مؤرشف · مرتبط حاليًا</small>' : '') +
              '</button>';
            }
            return '<button type="button" class="pro-picker-choice ' + (active ? 'is-selected' : '') + '" data-pro-picker-value="' + row.id + '">' +
              '<span class="pro-size-badge">' + escapeHtml(row.code || row.label) + '</span>' +
              '<strong>' + escapeHtml(row.label) + '</strong><small>' + escapeHtml(row.group || "") + (row.is_active === false ? ' · مؤرشف' : '') + '</small>' +
            '</button>';
          }).join("") : '<div class="pro-picker-empty">لا توجد سجلات متاحة.</div>') +
        '</div>' +
        allSizesSwitch +
        '<div class="pro-picker-footer"><button type="button" class="pro-primary-btn" data-pro-picker-apply>حفظ الاختيار</button></div>' +
      '</section>';

    document.body.appendChild(overlay);

    const colorPicker = $("[data-pro-new-color-picker]", overlay);
    const colorHex = $("[data-pro-new-color-hex]", overlay);
    const colorPreview = $("[data-pro-new-color-preview]", overlay);
    const syncNewColor = value => {
      const hex = String(value || "").trim();
      if (/^#[0-9a-fA-F]{6}$/.test(hex)) {
        if (colorPicker) colorPicker.value = hex;
        if (colorHex) colorHex.value = hex.toUpperCase();
        if (colorPreview) colorPreview.style.background = hex;
      }
    };
    if (type === "color") {
      syncNewColor(colorHex?.value || "#111111");
      colorPicker?.addEventListener("input", () => syncNewColor(colorPicker.value));
      colorHex?.addEventListener("input", () => {
        if (/^#[0-9a-fA-F]{6}$/.test(colorHex.value.trim())) syncNewColor(colorHex.value.trim());
      });
      $("[data-pro-create-color]", overlay)?.addEventListener("click", async () => {
        const name = String($("[data-pro-new-color-name]", overlay)?.value || "").trim();
        const hex = String(colorHex?.value || "").trim();
        if (!name) return notify("اكتب اسم اللون أولًا.", "error");
        if (!/^#[0-9a-fA-F]{6}$/.test(hex)) return notify("اكتب HEX صحيحًا مثل #FF0000.", "error");
        const button = $("[data-pro-create-color]", overlay);
        if (button) button.disabled = true;
        try {
          const created = await requestJson("/api/v1/catalog/reference/colors", {
            method:"POST",
            body:JSON.stringify({name,hex_code:hex.toUpperCase(),sort_order:0})
          });
          const item = created.item || {};
          if (!item.id) throw new Error("تعذر إنشاء اللون.");
          refs.colors = [...(refs.colors || []), {...item,is_active:true,selected:true}];
          const id = Number(item.id);
          pickerWorking.add(id);
          await persistDimensionsWithSets(pickerWorking, sizeIds);
          await generateMissingVariantsForSets(new Set([id]), sizeIds);
          overlay.remove();
          pickerType = null;
          await afterMutation();
          notify("تم إنشاء اللون وإضافته للمنتج دون تغيير متغيرات الألوان الأخرى.");
        } catch (error) {
          notify(error.message || "تعذر إنشاء اللون.","error");
          if (button) button.disabled = false;
        }
      });
    }

    const toggle = event => {
      const choice = event.target.closest("[data-pro-picker-value]");
      if (choice) {
        const id = Number(choice.dataset.proPickerValue);
        if (pickerWorking.has(id)) {
          pickerWorking.delete(id);
        } else {
          pickerWorking.add(id);
        }
        if (!pickerWorking.size) pickerWorking.add(id);
        choice.classList.toggle("is-selected", pickerWorking.has(id));
        return;
      }
      if (event.target.closest("[data-pro-picker-close]") || event.target === overlay) {
        overlay.remove();
        pickerType = null;
        return;
      }
      if (event.target.closest("[data-pro-picker-apply]")) applyPicker(overlay, previousIds);
    };
    overlay.addEventListener("click", toggle);
  };
  const persistDimensionsWithSets = async (nextColors, nextSizes) => requestJson(
    "/api/v1/catalog/products/" + productId + "/reference-dimensions",
    {method:"POST",body:JSON.stringify({
      color_ids:[...nextColors].map(Number),
      size_ids:[...nextSizes].map(Number)
    })}
  );

  const generateMissingVariantsForSets = async (nextColors, nextSizes) => {
    if (!nextColors.size || !nextSizes.size) return;
    await requestJson("/api/v1/catalog/products/" + productId + "/variants/generate", {
      method:"POST",
      body:JSON.stringify({
        color_ids:[...nextColors].map(Number),
        size_ids:[...nextSizes].map(Number)
      })
    });
  };

  const openSizeForColor = colorId => {
    const availableSizes = [...sizeIds].map(sizeById).filter(Boolean);
    const existing = new Set(activeVariants()
      .filter(v => Number(v.color_id) === Number(colorId))
      .map(v => Number(v.size_id)));
    const overlay = document.createElement("div");
    overlay.className = "pro-picker-backdrop";
    overlay.dataset.proSizeForColor = String(colorId);
    overlay.innerHTML =
      '<section class="pro-picker-sheet" role="dialog" aria-modal="true">' +
        '<div class="pro-picker-head"><div><h3>إضافة مقاس للون</h3><p>تظهر هنا المقاسات المحددة أعلى صفحة المتغيرات فقط.</p></div><button class="pro-picker-close" type="button" data-pro-size-close>×</button></div>' +
        '<div class="pro-size-list">' +
          (availableSizes.length ? availableSizes.map(size => {
            const id = Number(size.id);
            const has = existing.has(id);
            return '<label class="pro-size-list-item ' + (has ? 'is-existing' : '') + '">' +
              '<input type="checkbox" value="' + id + '" data-pro-size-choice' + (has ? ' disabled checked' : '') + '>' +
              '<span class="pro-size-badge">' + escapeHtml(size.code || size.label) + '</span>' +
              '<span><strong>' + escapeHtml(size.label) + '</strong><small>' + escapeHtml(size.group || "") + '</small></span>' +
              '<em>' + (has ? 'مضاف' : 'متاح') + '</em>' +
            '</label>';
          }).join("") : '<div class="pro-picker-empty">أضف المقاسات أولًا من قائمة المقاسات في أعلى القسم.</div>') +
        '</div>' +
        '<div class="pro-picker-footer"><button type="button" class="pro-primary-btn" data-pro-add-selected-sizes>إضافة المقاسات المحددة</button></div>' +
      '</section>';
    document.body.appendChild(overlay);
    overlay.addEventListener("click", async event => {
      if (event.target === overlay || event.target.closest("[data-pro-size-close]")) {
        overlay.remove();
        return;
      }
      if (!event.target.closest("[data-pro-add-selected-sizes]")) return;
      const selected = [...overlay.querySelectorAll("[data-pro-size-choice]:checked:not(:disabled)")].map(x => Number(x.value));
      if (!selected.length) return notify("هذا اللون يحتوي بالفعل على كل المقاسات المحددة.", "error");
      const button = event.target.closest("[data-pro-add-selected-sizes]");
      button.disabled = true;
      try {
        for (const sizeId of selected) {
          await requestJson("/api/v1/catalog/products/" + productId + "/variants", {
            method:"POST",
            body:JSON.stringify({color_id:Number(colorId),size_id:sizeId})
          });
        }
        overlay.remove();
        await afterMutation();
        notify("تمت إضافة المقاسات المحددة لهذا اللون.");
      } catch (error) {
        button.disabled = false;
        notify(error.message || "تعذر إضافة المقاسات.","error");
      }
    });
  };
  const applyPicker = async (overlay, previousIds = new Set()) => {
    const next = pickerWorking;
    if (!next.size) {
      notify(pickerType === "color" ? "اختر لونًا واحدًا على الأقل." : "اختر مقاسًا واحدًا على الأقل.", "error");
      return;
    }

    const mode = pickerType;
    const previous = new Set([...previousIds].map(Number));
    const newlyAdded = [...next].filter(id => !previous.has(Number(id))).map(Number);
    const addToAll = mode === "size" ? Boolean($("[data-pro-add-size-all]", overlay)?.checked) : false;

    try {
      if (mode === "color") {
        colorIds = new Set([...next].map(Number));
        await persistDimensions();
        if (newlyAdded.length) {
          await generateMissingVariantsForSets(new Set(newlyAdded), sizeIds);
        }
      } else {
        sizeIds = new Set([...next].map(Number));
        await persistDimensions();
        if (addToAll && newlyAdded.length) {
          await generateMissingVariantsForSets(colorIds, new Set(newlyAdded));
        }
      }

      overlay.remove();
      pickerType = null;
      await afterMutation();

      if (mode === "size") {
        notify(
          newlyAdded.length
            ? (addToAll
              ? "تم حفظ المقاسات الجديدة وإضافتها إلى جميع الألوان."
              : "تم حفظ المقاسات الجديدة. يمكنك إضافتها لكل لون بشكل مستقل من زر «إضافة».")
            : "تم حفظ اختيار المقاسات."
        );
      } else {
        notify(newlyAdded.length ? "تم حفظ الألوان وتجهيز متغيراتها الجديدة." : "تم حفظ اختيار الألوان.");
      }
    } catch (error) {
      notify(error.message, "error");
    }
  };


  const removeDimension = async (type, id) => {
    const set = type === "color" ? colorIds : sizeIds;
    if (set.size <= 1) {
      notify(type === "color" ? "لا يمكن إزالة آخر لون." : "لا يمكن إزالة آخر مقاس.", "error");
      return;
    }
    const row = type === "color" ? colorById(id) : sizeById(id);
    const label = row?.name || row?.label || "العنصر";
    if (!window.confirm("إزالة " + label + " من إعدادات المنتج؟\nالمتغيرات والطلبات السابقة لن تُحذف تلقائيًا.")) return;
    set.delete(Number(id));
    try {
      await persistDimensions();
      renderSelectedChips();
      await afterMutation();
      notify("تمت إزالة " + label + " من إعدادات المنتج.");
    } catch (error) {
      notify(error.message, "error");
    }
  };

  const renderGeneralMedia = () => {
    const all = snapshot?.media || [];
    const rows = all.filter(item => !item.color_id);
    const grid = $("#proGeneralMediaGrid");
    const count = $("#proGeneralMediaCount");
    const empty = $("#proGeneralMediaEmpty");
    if (count) count.textContent = String(rows.length);
    if (!grid) return;
    grid.innerHTML = rows.length
      ? rows.map(item =>
        '<article class="pro-general-item">' +
          '<img src="' + escapeHtml(item.url || "") + '" alt="' + escapeHtml(item.color_name || "صورة عامة") + '" loading="lazy">' +
          '<button class="delete" type="button" data-pro-media-delete="' + item.id + '" aria-label="حذف الصورة">×</button>' +
          '<button class="view" type="button" data-pro-media-view="' + item.id + '" aria-label="عرض الصورة">⌕</button>' +
        '</article>'
      ).join("")
      : "";
    if (empty) empty.hidden = rows.length > 0;
  };

  const renderSizeGuides = () => {
    const root = $("#proSizeGuideSelection");
    if (!root) return;
    const query = ($("#proSizeGuideSearch")?.value || "").trim().toLocaleLowerCase();
    const guides = (refs.size_guides || []).filter(guide =>
      !query ||
      String(guide.name || "").toLocaleLowerCase().includes(query) ||
      String(guide.guide_type || "").toLocaleLowerCase().includes(query) ||
      String(guide.fit_type || "").toLocaleLowerCase().includes(query)
    );
    root.innerHTML = guides.length
      ? guides.map(guide => {
          const id = Number(guide.id);
          const isSelected = sizeGuideIds.includes(id);
          const order = isSelected ? sizeGuideIds.indexOf(id) + 1 : 0;
          return '<article class="reference-choice-card ' + (isSelected ? 'is-selected' : '') + '" style="margin:0 12px 7px;padding:9px;grid-template-columns:minmax(0,1fr) auto">' +
            '<label style="display:grid;grid-template-columns:22px minmax(0,1fr);gap:8px;align-items:center">' +
              '<input type="checkbox" data-pro-size-guide="' + id + '"' + (isSelected ? ' checked' : '') + '>' +
              '<span class="reference-choice-copy"><strong>' + escapeHtml(guide.name) + '</strong><small>' + escapeHtml(guide.guide_type || "جدول مقاسات") + (order ? ' · الترتيب ' + order : '') + '</small></span>' +
            '</label>' +
            '<span style="display:flex;gap:4px;align-items:center">' +
              '<button class="pro-outline-btn" style="min-height:34px;width:36px;padding:0" type="button" data-pro-guide-up="' + id + '">↑</button>' +
              '<button class="pro-outline-btn" style="min-height:34px;width:36px;padding:0" type="button" data-pro-guide-down="' + id + '">↓</button>' +
            '</span>' +
          '</article>';
        }).join("")
      : '<div class="pro-picker-empty">لا توجد جداول مقاسات مطابقة.</div>';
  };

  const renderOptions = () => {
    const target = $("#proOptionsList");
    if (!target) return;
    const rows = snapshot?.options || [];
    target.innerHTML = rows.length
      ? rows.map(option =>
        '<article class="pro-option-record">' +
          '<div><strong>' + escapeHtml(option.name) + '</strong><small>' +
            escapeHtml(option.option_type || "custom") + ' · ' + ((option.values || []).length) + ' قيم' +
            (option.required ? ' · إجباري' : '') +
          '</small></div>' +
          '<div style="margin-top:7px;display:flex;flex-wrap:wrap;gap:5px">' +
            (option.values || []).map(value => '<span class="pro-selected-chip" style="min-height:30px">' + escapeHtml(value.label || "") + '</span>').join("") +
          '</div>' +
        '</article>'
      ).join("")
      : '<div class="pro-options-empty">لا توجد خيارات مخصصة لهذا المنتج بعد.</div>';
  };

  const renderVariantActionModal = variant => {
    const colorsRows = colors().filter(row => Number(row.id) !== Number(variant.color_id));
    let modal = document.querySelector("[data-pro-variant-modal]");
    if (!modal) {
      modal = document.createElement("div");
      modal.className = "pro-modal";
      modal.dataset.proVariantModal = "1";
      document.body.appendChild(modal);
    }
    modal.hidden = false;
    modal.innerHTML =
      '<div class="pro-modal-card">' +
        '<div class="pro-modal-head"><div><h3>إدارة المتغير</h3><p>' + escapeHtml(colorById(variant.color_id)?.name || "—") + ' · ' + escapeHtml(sizeById(variant.size_id)?.label || "—") + '</p></div><button class="pro-modal-close" type="button" data-pro-variant-close>×</button></div>' +
        '<form class="pro-variant-form" data-pro-variant-form>' +
          '<label>Barcode<input name="barcode" value="' + escapeHtml(variant.barcode || "") + '" dir="ltr" inputmode="numeric"></label>' +
          '<label>الوزن<input name="weight" type="number" min="0" step="0.0001" value="' + escapeHtml(variant.weight ?? "") + '" inputmode="decimal"></label>' +
          '<button class="pro-primary-btn" type="submit">حفظ بيانات المتغير</button>' +
        '</form>' +
        '<div style="height:1px;background:var(--pro-line);margin:12px 0"></div>' +
        '<div class="pro-modal-grid">' +
          '<button class="pro-outline-btn" type="button" data-pro-copy-variant>نسخ إلى لون آخر</button>' +
          '<button class="pro-outline-btn danger" type="button" data-pro-archive-variant>أرشفة المقاس</button>' +
        '</div>' +
        '<div class="pro-modal-actions" data-pro-copy-targets hidden style="margin-top:10px">' +
          '<label class="pro-variant-form">اللون الجديد<select data-pro-copy-color><option value="">اختر لونًا</option>' +
            colorsRows.map(row => '<option value="' + row.id + '">' + escapeHtml(row.name) + '</option>').join("") +
          '</select></label>' +
          '<button class="pro-primary-btn" type="button" data-pro-confirm-copy>نسخ المتغير</button>' +
        '</div>' +
      '</div>';

    const close = () => { modal.hidden = true; };
    $("[data-pro-variant-close]", modal)?.addEventListener("click", close);
    $$("[data-pro-variant-close]", modal).forEach(button => button.addEventListener("click", close));
    modal.addEventListener("click", event => {
      if (event.target === modal) close();
    }, {once:true});

    $("[data-pro-variant-form]", modal)?.addEventListener("submit", async event => {
      event.preventDefault();
      const form = new FormData(event.currentTarget);
      try {
        await requestJson("/api/v1/catalog/products/" + productId + "/variants/" + variant.id, {
          method:"PATCH",
          body:JSON.stringify({
            sku:variant.sku,
            color_id:variant.color_id || null,
            size_id:variant.size_id || null,
            barcode:String(form.get("barcode") || "").trim(),
            weight:form.get("weight") || null
          })
        });
        close();
        await afterMutation();
        notify("تم حفظ تفاصيل المتغير.");
      } catch (error) { notify(error.message,"error"); }
    });

    $("[data-pro-copy-variant]", modal)?.addEventListener("click", () => {
      const box = $("[data-pro-copy-targets]", modal);
      if (box) box.hidden = !box.hidden;
    });

    $("[data-pro-confirm-copy]", modal)?.addEventListener("click", async () => {
      const target = Number($("[data-pro-copy-color]", modal)?.value || 0);
      if (!target) return notify("اختر اللون الجديد أولًا.","error");
      try {
        await requestJson("/api/v1/catalog/products/" + productId + "/variants/" + variant.id + "/copy", {
          method:"POST",
          body:JSON.stringify({color_id:target})
        });
        close();
        await afterMutation();
        notify("تم نسخ المقاس والمخزون والوزن إلى اللون الجديد.");
      } catch (error) { notify(error.message,"error"); }
    });

    $("[data-pro-archive-variant]", modal)?.addEventListener("click", async () => {
      if (!window.confirm("أرشفة هذا المتغير؟ سيختفي من الاختيارات الجديدة ولن يُحذف سجل الطلبات السابق.")) return;
      try {
        await requestJson("/api/v1/catalog/products/" + productId + "/variants/" + variant.id, {method:"DELETE"});
        close();
        await afterMutation();
        notify("تمت أرشفة المتغير.");
      } catch (error) { notify(error.message,"error"); }
    });
  };

  const deleteColorSize = async (colorId, sizeId) => {
    const color = colorById(colorId);
    const size = sizeById(sizeId);
    const label = (color?.name || "اللون") + " · " + (size?.label || "المقاس");
    const variants = activeVariants().filter(v =>
      Number(v.color_id) === Number(colorId) && Number(v.size_id) === Number(sizeId)
    );

    if (!window.confirm(
      "حذف " + label + " من هذا اللون؟\n\n" +
      "سيتم حذف/أرشفة المتغير المرتبط بهذا اللون والمقاس فقط. " +
      "المقاس سيبقى متاحًا لبقية الألوان."
    )) return;

    try {
      for (const variant of variants) {
        await requestJson("/api/v1/catalog/products/" + productId + "/variants/" + variant.id, {
          method:"DELETE"
        });
      }
      await afterMutation();
      notify("تمت إزالة " + (size?.label || "المقاس") + " من اللون " + (color?.name || "المحدد") + ".");
    } catch (error) {
      notify(error.message || "تعذر حذف المقاس من اللون.","error");
    }
  };

  const deleteColorAndContents = async colorId => {
    const color = colorById(colorId);
    const variants = activeVariants().filter(v => Number(v.color_id) === Number(colorId));
    const media = (snapshot?.media || []).filter(m => Number(m.color_id) === Number(colorId));
    const label = color?.name || "هذا اللون";

    if (!window.confirm(
      "حذف اللون «" + label + "» بالكامل من هذا المنتج؟\n\n" +
      "سيتم حذف/أرشفة جميع متغيراته وصوره الخاصة به، ثم إزالته من ألوان المنتج.\n" +
      "هذا لا يحذف اللون من جدول الألوان العام."
    )) return;

    try {
      for (const variant of variants) {
        await requestJson("/api/v1/catalog/products/" + productId + "/variants/" + variant.id, {
          method:"DELETE"
        });
      }
      for (const item of media) {
        await requestJson("/api/v1/catalog/products/" + productId + "/media/" + item.id, {
          method:"DELETE"
        });
      }

      colorIds.delete(Number(colorId));
      await persistDimensions();
      await afterMutation();
      renderSelectedChips();
      notify("تم حذف اللون «" + label + "» ومتغيراته وصوره من المنتج.");
    } catch (error) {
      notify(error.message || "تعذر حذف اللون بالكامل.","error");
    }
  };

  const renderVariants = () => {
    const target = $("#proVariantsList");
    if (!target) return;

    const selectedColors = [...colorIds].map(colorById).filter(Boolean);
    const selectedSizes = [...sizeIds].map(sizeById).filter(Boolean);
    const variants = activeVariants();

    const total = variants.filter(v => colorIds.has(Number(v.color_id)) && sizeIds.has(Number(v.size_id))).length;
    const count = $("#proVariantCount");
    if (count) count.textContent = String(total);

    if (!selectedColors.length) {
      target.innerHTML = '<div class="pro-picker-empty">ابدأ بإضافة لون واحد على الأقل.</div>';
      return;
    }

    target.innerHTML = selectedColors.map((color,index) => {
      const allColorVariants = variants.filter(v => Number(v.color_id) === Number(color.id));
      const colorVariants = allColorVariants.filter(v => sizeIds.has(Number(v.size_id)));
      const legacyVariants = allColorVariants.filter(v => !sizeIds.has(Number(v.size_id)));
      const colorSizeIds = [
        ...selectedSizes.filter(size => colorVariants.some(v => Number(v.size_id) === Number(size.id))).map(size => Number(size.id)),
        ...legacyVariants.map(v => Number(v.size_id)).filter(id => id && !selectedSizes.some(size => Number(size.id) === id))
      ];
      const colorSizes = colorSizeIds.map(sizeById).filter(Boolean);
      const stockAvailable = allColorVariants.reduce((sum,v) => sum + Number(stockForLocation(v.id)?.available || 0), 0);
      const colorMedia = (snapshot.media || []).filter(m => Number(m.color_id) === Number(color.id));
      const missingSizes = selectedSizes.filter(size => !allColorVariants.some(v => Number(v.size_id) === Number(size.id)));
      const headerCells = colorSizes.map(size =>
        '<th scope="col">' +
          '<div class="pro-size-head">' +
            '<div class="pro-size-head-main"><span class="pro-size-label">' + escapeHtml(size.label) + '</span><small>' + escapeHtml(size.code || size.group || "") + '</small></div>' +
            '<button type="button" class="pro-size-remove" data-pro-remove-color-size="' + color.id + '" data-pro-remove-size-id="' + size.id + '" aria-label="حذف المقاس من اللون">×</button>' +
          '</div>' +
        '</th>'
      ).join("");

      const cells = colorSizes.map(size => {
        const variant = variantFor(color.id, size.id) || allColorVariants.find(v => Number(v.size_id) === Number(size.id));
        if (!variant) return '';
        const stock = stockForLocation(variant.id);
        const onHand = Number(stock?.on_hand || 0);
        const reserved = Number(stock?.reserved || 0);
        const available = Number(stock?.available ?? Math.max(0,onHand-reserved));
        return '<td class="pro-stock-cell" data-pro-stock-cell="' + variant.id + '">' +
          '<div class="pro-stock-main"><input type="number" min="0" step="1" inputmode="numeric" value="' + onHand + '" data-pro-stock-input data-variant-id="' + variant.id + '" aria-label="مخزون ' + escapeHtml(color.name) + ' ' + escapeHtml(size.label) + '">' +
          '<span class="pro-stock-unit">كمية المخزون</span></div>' +
          '<div class="pro-stock-meta"><span><strong data-pro-stock-available>متاح ' + available + '</strong></span><span>محجوز ' + reserved + '</span></div>' +
          '<div class="pro-stock-tools"><span class="pro-save-state" data-pro-save-state>محفوظ</span><button type="button" class="pro-dots" data-pro-variant-actions="' + variant.id + '" aria-label="إجراءات المتغير">⋯</button></div>' +
        '</td>';
      }).join("");

      const addButton = '<button type="button" class="pro-add-size-button pro-inline-add" data-pro-add-size-column="' + color.id + '">＋ إضافة</button>';

      if (!colorSizes.length) {
        return '<article class="pro-color-card" data-pro-color-card="' + color.id + '">' +
          '<header class="pro-color-card-head">' +
            '<div class="pro-color-identity"><span class="pro-swatch" style="background:' + escapeHtml(color.hex_code || "#e5e7eb") + '"></span><div class="pro-color-title"><strong>' + escapeHtml(color.name) + '</strong><small>لا توجد مقاسات مضافة لهذا اللون</small></div></div>' +
            '<div style="display:flex;align-items:center;gap:6px"><span class="pro-color-status ' + (stockAvailable > 0 ? 'is-good' : '') + '">' + (stockAvailable > 0 ? ('متوفر · ' + stockAvailable) : 'بدون متاح') + '</span><button type="button" class="pro-card-menu-button" data-pro-remove-color-card="' + color.id + '" aria-label="إزالة اللون">⋯</button></div>' +
          '</header>' +
          '<section class="pro-color-images">' +
            '<div class="pro-color-images-head"><div><strong>صور ' + escapeHtml(color.name) + '</strong><small>' + colorMedia.length + ' صورة</small></div><button type="button" class="pro-outline-btn" data-pro-add-color-image="' + color.id + '">＋ إضافة</button></div>' +
            '<div class="pro-image-rail">' +
              colorMedia.map(item =>
                '<div class="pro-image-item"><img src="' + escapeHtml(item.url || "") + '" alt="' + escapeHtml(color.name) + '" loading="lazy">' +
                  '<button class="pro-image-x" type="button" data-pro-color-image-delete="' + item.id + '" aria-label="حذف الصورة">×</button>' +
                  '<button class="pro-image-view" type="button" data-pro-color-image-view="' + item.id + '">⌕</button>' +
                '</div>'
              ).join("") +
              '<button type="button" class="pro-image-add" data-pro-add-color-image="' + color.id + '"><span>＋</span>إضافة صورة</button>' +
            '</div>' +
          '</section>' +
          '<div class="pro-no-sizes"><div><strong>لا يوجد مقاس لهذا اللون حتى الآن.</strong><small>زر «إضافة» يعرض المقاسات المحددة أعلى القسم فقط.</small></div>' + addButton + '</div>' +
        '</article>';
      }

      return '<article class="pro-color-card" data-pro-color-card="' + color.id + '">' +
        '<header class="pro-color-card-head">' +
          '<div class="pro-color-identity"><span class="pro-swatch" style="background:' + escapeHtml(color.hex_code || "#e5e7eb") + '"></span><div class="pro-color-title"><strong>' + escapeHtml(color.name) + '</strong><small>' + colorSizes.length + ' مقاسات · ' + (colorMedia.length ? colorMedia.length + ' صور' : 'بدون صور') + '</small></div></div>' +
          '<div style="display:flex;align-items:center;gap:6px"><span class="pro-color-status ' + (stockAvailable > 0 ? 'is-good' : '') + '">' + (stockAvailable > 0 ? ('متوفر · ' + stockAvailable) : 'بدون متاح') + '</span><button type="button" class="pro-card-menu-button" data-pro-remove-color-card="' + color.id + '" aria-label="إزالة اللون">⋯</button></div>' +
        '</header>' +
        '<section class="pro-color-images">' +
          '<div class="pro-color-images-head"><div><strong>صور ' + escapeHtml(color.name) + '</strong><small>' + colorMedia.length + ' صورة</small></div><button type="button" class="pro-outline-btn" data-pro-add-color-image="' + color.id + '">＋ إضافة</button></div>' +
          '<div class="pro-image-rail">' +
            colorMedia.map(item =>
              '<div class="pro-image-item"><img src="' + escapeHtml(item.url || "") + '" alt="' + escapeHtml(color.name) + '" loading="lazy">' +
                '<button class="pro-image-x" type="button" data-pro-color-image-delete="' + item.id + '" aria-label="حذف الصورة">×</button>' +
                '<button class="pro-image-view" type="button" data-pro-color-image-view="' + item.id + '">⌕</button>' +
              '</div>'
            ).join("") +
            '<button type="button" class="pro-image-add" data-pro-add-color-image="' + color.id + '"><span>＋</span>إضافة صورة</button>' +
          '</div>' +
        '</section>' +
        '<div class="pro-variant-table-wrap"><table class="pro-variant-table">' +
          '<thead><tr>' + headerCells + '<th class="pro-add-col" rowspan="2">' + addButton + '</th></tr></thead>' +
          '<tbody><tr>' + cells + '</tr></tbody>' +
        '</table></div>' +
        '<footer class="pro-card-footer"><small>الباركود والوزن والأرشفة من ⋯ داخل كل متغير.</small></footer>' +
      '</article>';
    }).join("");
  };

  const saveStock = async input => {
    const variantId = Number(input.dataset.variantId || 0);
    if (!variantId || !selectedLocationId) return;
    const row = stockForLocation(variantId);
    const reserved = Number(row?.reserved || 0);
    const reorder = Number(row?.reorder_level || 0);
    const onHand = Math.max(0, Number(input.value || 0));
    const state = input.closest("[data-pro-stock-cell]")?.querySelector("[data-pro-save-state]");
    const cell = input.closest("[data-pro-stock-cell]");
    if (onHand < reserved) {
      input.setCustomValidity("المخزون لا يمكن أن يكون أقل من المحجوز.");
      input.reportValidity();
      if (state) { state.textContent = "خطأ"; state.className = "pro-save-state is-error"; }
      return;
    }
    input.setCustomValidity("");
    const key = variantId + ":" + selectedLocationId;
    if (state) { state.textContent = "جارٍ الحفظ…"; state.className = "pro-save-state is-saving"; }

    const previous = stockRequests.get(key);
    if (previous) await previous;

    const req = requestJson("/api/v1/catalog/products/" + productId + "/inventory", {
      method:"POST",
      body:JSON.stringify({
        variant_id:variantId,
        location_id:selectedLocationId,
        on_hand:onHand,
        reserved,
        reorder_level:reorder
      })
    });
    stockRequests.set(key, req);
    try {
      const result = await req;
      patchStock(result.item);
      input.value = Number(result.item.on_hand || 0);
      const available = cell?.querySelector("[data-pro-stock-available]");
      if (available) available.textContent = "متاح " + Number(result.item.available || 0);
      if (state) { state.textContent = "تم الحفظ"; state.className = "pro-save-state is-saved"; }
    } catch (error) {
      if (state) { state.textContent = error.message || "تعذر الحفظ"; state.className = "pro-save-state is-error"; }
    } finally {
      if (stockRequests.get(key) === req) stockRequests.delete(key);
    }
  };

  const queueStock = input => {
    const id = input.dataset.variantId;
    clearTimeout(stockTimers.get(id));
    stockTimers.set(id, setTimeout(() => {
      stockTimers.delete(id);
      saveStock(input);
    }, 650));
  };

  const uploadImages = async colorId => {
    const input = $("#proColorImageInput");
    if (!input || !input.files.length) {
      notify("اختر صورة واحدة على الأقل.", "error");
      return;
    }
    const body = new FormData();
    [...input.files].forEach(file => body.append("files", file));
    if (colorId) body.append("color_id", String(colorId));
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/media", {method:"POST",body});
      input.value = "";
      pendingImageColorId = null;
      await afterMutation();
      notify(colorId ? "تمت إضافة صور اللون." : "تمت إضافة الصور العامة.");
    } catch (error) { notify(error.message,"error"); }
  };

  const showImage = item => {
    previewItem = item;
    const modal = $("[data-pro-image-modal]");
    if (!modal) return;
    modal.hidden = false;
    document.body.classList.add("pro-modal-open");
    $("[data-pro-modal-title]", modal).textContent = item.color_id
      ? "صور " + (colorById(item.color_id)?.name || item.color_name || "اللون")
      : "صورة عامة للمنتج";
    $("[data-pro-modal-subtitle]", modal).textContent = item.color_id
      ? "يمكنك إضافة صور أخرى لهذا اللون من الزر أدناه."
      : "يمكنك إضافة صور عامة أخرى من الزر أدناه.";
    $("[data-pro-modal-image]", modal).src = item.url || "";
    $("[data-pro-modal-image]", modal).alt = item.color_name || "صورة المنتج";
    const add = $("[data-pro-modal-add]", modal);
    if (add) add.textContent = item.color_id ? "＋ إضافة صورة لهذا اللون" : "＋ إضافة صورة عامة";
  };

  const closeImage = () => {
    const modal = $("[data-pro-image-modal]");
    if (modal) modal.hidden = true;
    document.body.classList.remove("pro-modal-open");
    previewItem = null;
  };

  const deleteMedia = async itemId => {
    if (!window.confirm("حذف هذه الصورة نهائيًا من وسائط المنتج؟")) return;
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/media/" + itemId, {method:"DELETE"});
      closeImage();
      await afterMutation();
      notify("تم حذف الصورة.");
    } catch (error) { notify(error.message,"error"); }
  };

  const handleNavigation = key => {
    $$("[data-pro-panel]").forEach(panel => {
      const active = panel.dataset.proPanel === key;
      panel.hidden = !active;
    });
    $$(".pro-step").forEach(button => button.classList.toggle("is-active", button.dataset.proStep === key));
    window.scrollTo({top:0,behavior:"smooth"});
  };

  const refreshData = async () => {
    try {
      const [productResponse, configResponse] = await Promise.all([
        requestJson("/api/v1/catalog/products/" + productId + "/wizard"),
        requestJson("/api/v1/catalog/reference/product-config?product_id=" + encodeURIComponent(productId))
      ]);
      snapshot = productResponse.item || productResponse;
      const config = configResponse.item || configResponse || {};
      refs = {...refs,...config};

      hydrateSelections();
      renderLocation();
      renderSelectedChips();
      renderVariants();
      renderGeneralMedia();
      renderSizeGuides();
      renderOptions();
    } catch (error) {
      notify(error.message || "تعذر تحميل بيانات تعديل برو.","error");
    }
  };

  $("#proAddColor")?.addEventListener("click", () => openPicker("color"));
  $("#proAddSize")?.addEventListener("click", () => openPicker("size"));

  $("#proSelectedColors")?.addEventListener("click", event => {
    const button = event.target.closest("[data-remove-color]");
    if (button) removeDimension("color", Number(button.dataset.removeColor));
  });
  $("#proSelectedSizes")?.addEventListener("click", event => {
    const button = event.target.closest("[data-remove-size]");
    if (button) removeDimension("size", Number(button.dataset.removeSize));
  });

  $("#proVariantsList")?.addEventListener("input", event => {
    const input = event.target.closest("[data-pro-stock-input]");
    if (input) queueStock(input);
  });

  $("#proVariantsList")?.addEventListener("blur", event => {
    const input = event.target.closest("[data-pro-stock-input]");
    if (input) {
      clearTimeout(stockTimers.get(input.dataset.variantId));
      saveStock(input);
    }
  }, true);

  $("#proVariantsList")?.addEventListener("keydown", event => {
    const input = event.target.closest("[data-pro-stock-input]");
    if (input && event.key === "Enter") {
      event.preventDefault();
      input.blur();
    }
  });

  $("#proVariantsList")?.addEventListener("click", async event => {
    const action = event.target.closest("[data-pro-variant-actions]");
    if (action) {
      const variant = activeVariants().find(v => Number(v.id) === Number(action.dataset.proVariantActions));
      if (variant) renderVariantActionModal(variant);
      return;
    }

    const addSize = event.target.closest("[data-pro-add-size-column]");
    if (addSize) {
      openSizeForColor(Number(addSize.dataset.proAddSizeColumn));
      return;
    }

    const create = event.target.closest("[data-pro-create-variant-color]");
    if (create) {
      try {
        await requestJson("/api/v1/catalog/products/" + productId + "/variants", {
          method:"POST",
          body:JSON.stringify({
            color_id:Number(create.dataset.proCreateVariantColor),
            size_id:Number(create.dataset.proCreateVariantSize)
          })
        });
        await afterMutation();
        notify("تم إنشاء المتغير وSKU تلقائيًا.");
      } catch (error) { notify(error.message,"error"); }
      return;
    }

    const removeColorSize = event.target.closest("[data-pro-remove-color-size]");
    if (removeColorSize) {
      await deleteColorSize(
        Number(removeColorSize.dataset.proRemoveColorSize),
        Number(removeColorSize.dataset.proRemoveSizeId)
      );
      return;
    }

    const removeColor = event.target.closest("[data-pro-remove-color-card]");
    if (removeColor) {
      await deleteColorAndContents(Number(removeColor.dataset.proRemoveColorCard));
      return;
    }

    const deleteImage = event.target.closest("[data-pro-color-image-delete]");
    if (deleteImage) {
      deleteMedia(Number(deleteImage.dataset.proColorImageDelete));
      return;
    }

    const viewImage = event.target.closest("[data-pro-color-image-view]");
    if (viewImage) {
      const item = (snapshot?.media || []).find(x => Number(x.id) === Number(viewImage.dataset.proColorImageView));
      if (item) showImage(item);
      return;
    }

    const addImage = event.target.closest("[data-pro-add-color-image]");
    if (addImage) {
      pendingImageColorId = Number(addImage.dataset.proAddColorImage);
      $("#proColorImageInput")?.click();
    }
  });

  $("#proInventoryLocation")?.addEventListener("change", event => {
    selectedLocationId = Number(event.currentTarget.value || 0) || null;
    try {
      if (selectedLocationId) localStorage.setItem("takhfid:product-stock-location:" + productId, String(selectedLocationId));
    } catch (error) {}
    renderVariants();
  });

  $("#proGeneralMediaGrid")?.addEventListener("click", event => {
    const del = event.target.closest("[data-pro-media-delete]");
    if (del) {
      deleteMedia(Number(del.dataset.proMediaDelete));
      return;
    }
    const view = event.target.closest("[data-pro-media-view]");
    if (view) {
      const item = (snapshot?.media || []).find(x => Number(x.id) === Number(view.dataset.proMediaView));
      if (item) showImage(item);
    }
  });

  $("#proUploadGeneralMedia")?.addEventListener("click", () => {
    pendingImageColorId = null;
    $("#proGeneralMediaInput")?.click();
  });

  $("#proGeneralMediaInput")?.addEventListener("change", () => {
    const input = $("#proGeneralMediaInput");
    if (!input?.files.length) return;
    const body = new FormData();
    [...input.files].forEach(file => body.append("files", file));
    requestJson("/api/v1/catalog/products/" + productId + "/media", {method:"POST",body})
      .then(async () => {
        input.value = "";
        await afterMutation();
        notify("تم رفع الصور العامة وتحسينها.");
      })
      .catch(error => notify(error.message,"error"));
  });

  $("#proColorImageInput")?.addEventListener("change", () => uploadImages(pendingImageColorId));

  $$("[data-pro-close]").forEach(button => button.addEventListener("click", closeImage));
  $("[data-pro-image-modal]")?.addEventListener("click", event => {
    if (event.target.matches("[data-pro-image-modal]")) closeImage();
  });
  $("[data-pro-modal-add]")?.addEventListener("click", () => {
    const colorId = previewItem?.color_id ? Number(previewItem.color_id) : null;
    pendingImageColorId = colorId;
    $("#proColorImageInput")?.click();
  });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape") closeImage();
  });

  $("#proSizeGuideSearch")?.addEventListener("input", renderSizeGuides);
  $("#proSizeGuideSelection")?.addEventListener("change", event => {
    const input = event.target.closest("[data-pro-size-guide]");
    if (!input) return;
    const id = Number(input.dataset.proSizeGuide);
    if (input.checked) {
      if (!sizeGuideIds.includes(id)) sizeGuideIds.push(id);
    } else {
      sizeGuideIds = sizeGuideIds.filter(x => x !== id);
    }
    renderSizeGuides();
  });
  $("#proSizeGuideSelection")?.addEventListener("click", event => {
    const up = event.target.closest("[data-pro-guide-up]");
    const down = event.target.closest("[data-pro-guide-down]");
    const button = up || down;
    if (!button) return;
    const id = Number(button.dataset.proGuideUp || button.dataset.proGuideDown);
    const index = sizeGuideIds.indexOf(id);
    const next = index + (up ? -1 : 1);
    if (index < 0 || next < 0 || next >= sizeGuideIds.length) return;
    [sizeGuideIds[index], sizeGuideIds[next]] = [sizeGuideIds[next], sizeGuideIds[index]];
    renderSizeGuides();
  });

  $("#proSaveSizeGuides")?.addEventListener("click", async () => {
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/size-guides", {
        method:"POST",
        body:JSON.stringify({guide_ids:sizeGuideIds})
      });
      await afterMutation();
      notify(sizeGuideIds.length ? "تم حفظ جداول المقاسات وترتيبها." : "تم إلغاء ربط جداول المقاسات.");
    } catch (error) { notify(error.message,"error"); }
  });

  $("#proOptionForm")?.addEventListener("submit", async event => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const values = String(form.get("values_text") || "")
      .split("\\n").map(x => x.trim()).filter(Boolean).map(label => ({label}));
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/options", {
        method:"POST",
        body:JSON.stringify({
          name:String(form.get("name") || "").trim(),
          option_type:"custom",
          required:form.get("required") === "on",
          values
        })
      });
      event.currentTarget.reset();
      await afterMutation();
      notify("تمت إضافة الخيار المخصص للمنتج.");
    } catch (error) { notify(error.message,"error"); }
  });

  $$("[data-pro-step]").forEach(button => {
    button.addEventListener("click", () => handleNavigation(button.dataset.proStep));
  });

  $("#locationForm")?.addEventListener("submit", () => {
    setTimeout(async () => {
      syncLegacyWizard();
      await refreshData();
      notify("تمت إضافة موقع التخزين.");
    }, 900);
  });

  ["quickColorForm","quickSizeForm"].forEach(id => {
    $("#" + id)?.addEventListener("submit", () => {
      setTimeout(async () => {
        await syncLegacyWizard();
        await refreshData();
      }, 900);
    });
  });

  $("#proSizeGuideSelection")?.addEventListener("keydown", event => {
    if (event.key === "Enter") event.preventDefault();
  });

  const decorateCategoryTree = () => {
    const root = $("#categorySelection");
    if (!root) return;
    const nodes = $(".category-picker-node", root);
    nodes.forEach(node => {
      if (node.dataset.proTreeReady === "1") return;
      node.dataset.proTreeReady = "1";
      const children = [...node.children].filter(child => child.classList.contains("category-picker-node"));
      if (!children.length) return;
      const marker = $(".category-picker-marker", node);
      if (marker) {
        marker.textContent = "›";
        marker.setAttribute("role","button");
        marker.setAttribute("tabindex","0");
        marker.setAttribute("aria-expanded","false");
      }
      node.classList.add("is-collapsed");
    });
    const selected = $(".category-picker-node", root).filter(node => $("input[data-category-checkbox]:checked", node));
    selected.forEach(node => {
      let current = node;
      while (current && current !== root) {
        if (current.classList.contains("category-picker-node")) {
          current.classList.remove("is-collapsed");
          const marker = $(".category-picker-marker", current);
          if (marker) {
            marker.textContent = "⌄";
            marker.setAttribute("aria-expanded","true");
          }
        }
        current = current.parentElement?.closest?.(".category-picker-node");
      }
    });
  };

  const filterCategoryTree = () => {
    const root = $("#categorySelection");
    if (!root) return;
    const query = String($("#categorySearch")?.value || "").trim().toLocaleLowerCase();
    const nodes = $(".category-picker-node", root);
    nodes.forEach(node => node.classList.remove("is-filter-hidden"));
    if (!query) {
      decorateCategoryTree();
      return;
    }
    const matchNode = node => {
      const text = String(node.textContent || "").toLocaleLowerCase();
      const ownMatch = text.includes(query);
      const childMatch = [...node.children]
        .filter(child => child.classList.contains("category-picker-node"))
        .some(child => matchNode(child));
      if (!ownMatch && !childMatch) node.classList.add("is-filter-hidden");
      if (childMatch) node.classList.remove("is-collapsed");
      const marker = $(".category-picker-marker", node);
      if (marker && childMatch) { marker.textContent = "⌄"; marker.setAttribute("aria-expanded","true"); }
      return ownMatch || childMatch;
    };
    $(".category-picker-node", root).filter(node => !node.parentElement.closest(".category-picker-node")).forEach(matchNode);
  };

  $("#categorySelection")?.addEventListener("click", event => {
    const marker = event.target.closest(".category-picker-marker");
    if (!marker) return;
    event.preventDefault();
    event.stopPropagation();
    const node = marker.closest(".category-picker-node");
    if (!node) return;
    const collapsed = node.classList.toggle("is-collapsed");
    marker.textContent = collapsed ? "›" : "⌄";
    marker.setAttribute("aria-expanded", String(!collapsed));
  });

  $("#categorySelection")?.addEventListener("keydown", event => {
    if ((event.key === "Enter" || event.key === " ") && event.target.closest(".category-picker-marker")) {
      event.preventDefault();
      event.target.click();
    }
  });

  $("#categorySearch")?.addEventListener("input", filterCategoryTree);

  const categoryObserver = new MutationObserver(() => {
    requestAnimationFrame(() => {
      decorateCategoryTree();
      filterCategoryTree();
    });
  });
  if ($("#categorySelection")) categoryObserver.observe($("#categorySelection"), {childList:true,subtree:true});

  renderLocation();
  handleNavigation("basics");
  setTimeout(() => {
    refreshData();
    setTimeout(decorateCategoryTree, 120);
  }, 30);
})();
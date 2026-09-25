(() => {
  const shell = document.querySelector(".wizard-shell");
  if (!shell) return;

  const productId = shell.dataset.productId;
  const message = document.getElementById("wizardMessage");
  const panels = [...document.querySelectorAll(".wizard-panel")];
  const steps = [...document.querySelectorAll(".wizard-step")];
  let snapshot = null;
  let policyRefs = null;
  let marketingRefs = null;
  let optionRefs = null;

  const notify = (text, type = "success") => {
    message.textContent = text;
    message.className = "alert " + type;
    message.hidden = false;
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const requestJson = async (url, options = {}) => {
    const headers = options.body instanceof FormData
      ? {}
      : { "Content-Type": "application/json" };
    const response = await fetch(url, {
      cache: "no-store",
      ...options,
      headers: { ...headers, ...(options.headers || {}) },
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.detail || data.error || "تعذر تنفيذ العملية");
    return data;
  };

  const load = async () => {
    try {
      const [result, refs, marketing, options] = await Promise.all([
        requestJson("/api/v1/catalog/products/" + productId + "/wizard"),
        requestJson("/api/v1/catalog/reference/policies"),
        requestJson("/api/v1/catalog/reference/marketing"),
        requestJson("/api/v1/catalog/reference/options?product_id=" + encodeURIComponent(productId)),
      ]);
      snapshot = result.item;
      policyRefs = refs;
      marketingRefs = marketing;
      optionRefs = options.item || options;
      hydrate();
    } catch (error) {
      notify(error.message, "error");
    }
  };

  const hydrate = () => {
    const selected = new Set((snapshot.categories || []).map(x => String(x.id)));
    document.querySelectorAll("[data-category-checkbox]").forEach((input) => {
      input.checked = selected.has(input.value);
    });

    document.getElementById("optionsList").innerHTML = (snapshot.options || []).map(option => (
      '<details class="panel" style="padding:12px">' +
      '<summary><strong>' + escapeHtml(option.name) + '</strong><span class="muted"> · ' + escapeHtml(option.option_type) + ' · ' + ((option.values || []).length) + ' قيم</span></summary>' +
      '<form class="form-stack option-edit-form" data-option-id="' + option.id + '" style="margin-top:10px">' +
      '<label>اسم الخيار<input name="name" value="' + escapeHtml(option.name) + '" required></label>' +
      '<label>النوع<select name="option_type"><option value="color" ' + (option.option_type==="color"?"selected":"") + '>لون</option><option value="size" ' + (option.option_type==="size"?"selected":"") + '>مقاس</option><option value="custom" ' + (option.option_type==="custom"?"selected":"") + '>مخصص</option></select></label>' +
      '<label class="check-row"><input name="required" type="checkbox" ' + (option.required?"checked":"") + '><span><strong>إجباري</strong></span></label>' +
      '<label>قيم الخيار<textarea name="values_text" rows="4">' + escapeHtml((option.values || []).map(v => v.label).join("\n")) + '</textarea></label>' +
      '<div class="modal-actions"><button class="primary-button" type="submit">حفظ الخيار</button><button class="ghost-button" type="button" data-delete-option="' + option.id + '">حذف الخيار</button></div>' +
      '</form></details>'
    )).join("");

    document.getElementById("variantsList").innerHTML = (snapshot.variants || []).map(variant => (
      '<details class="panel" style="padding:12px">' +
      '<summary><strong>' + escapeHtml(variant.sku) + '</strong><span class="muted"> · Color ' + (variant.color_id || "—") + ' · Size ' + (variant.size_id || "—") + '</span></summary>' +
      '<form class="form-stack variant-edit-form" data-variant-id="' + variant.id + '" style="margin-top:10px">' +
      '<label>SKU<input name="sku" value="' + escapeHtml(variant.sku) + '" required dir="ltr"></label>' +
      '<label>اللون<select name="color_id" data-current="' + (variant.color_id || "") + '"></select></label>' +
      '<label>المقاس<select name="size_id" data-current="' + (variant.size_id || "") + '"></select></label>' +
      '<label>Barcode<input name="barcode" value="' + escapeHtml(variant.barcode || "") + '" dir="ltr"></label>' +
      '<label>الوزن<input name="weight" type="number" min="0" step="0.0001" value="' + escapeHtml(variant.weight || "") + '"></label>' +
      '<div class="modal-actions"><button class="primary-button" type="submit">حفظ المتغير</button><button class="ghost-button" type="button" data-archive-variant="' + variant.id + '">أرشفة المتغير</button></div>' +
      '</form></details>'
    )).join("");

    const mediaRows = snapshot.media || [];
    const mediaCard = (item) => (
      '<div class="media-thumb">' +
      (item.url ? '<img src="' + escapeHtml(item.url) + '" alt="' + escapeHtml(item.color_name || "صورة المنتج") + '">' : '<span>صورة</span>') +
      '<div class="media-thumb-meta"><small>' + (item.color_name ? escapeHtml(item.color_name) : 'عام') + '</small><small>#' + item.id + '</small></div>' +
      '<button type="button" class="ghost-button" data-delete-media="' + item.id + '">حذف</button></div>'
    );
    document.getElementById("mediaPreview").innerHTML = mediaRows.map(mediaCard).join("");
    document.getElementById("mediaTotalCount").textContent = mediaRows.length + " صورة";

    const colors = optionRefs?.colors || [];
    const usedColorIds = new Set((snapshot.variants || []).map(v => v.color_id).filter(Boolean).map(Number));
    document.getElementById("productColorCount").textContent = usedColorIds.size;
    document.getElementById("productColors").innerHTML = colors.length
      ? colors.map(color => {
          const used = usedColorIds.has(Number(color.id));
          const bg = color.hex_code || "#111827";
          return '<div class="swatch-card ' + (used ? "is-used" : "") + '">' +
            '<span class="color-swatch large" style="background:' + escapeHtml(bg) + '"></span>' +
            '<div class="swatch-copy"><strong>' + escapeHtml(color.name) + '</strong><small>' + (used ? "مستخدم في متغير" : "متاح") + '</small></div>' +
            '<button class="ghost-button use-color-button" type="button" data-use-color="' + color.id + '">' + (used ? "استخدام" : "＋ إضافة للمتغير") + '</button>' +
          '</div>';
        }).join("")
      : '<div class="empty-state compact"><strong>لا توجد ألوان.</strong><span class="muted">أضف أول لون من الزر أعلاه.</span></div>';

    document.getElementById("availableSizeCount").textContent = (optionRefs?.sizes || []).length;
    document.getElementById("sizeReferencePreview").innerHTML = (optionRefs?.sizes || []).slice(0, 18).map(size => (
      '<span class="size-chip"><strong>' + escapeHtml(size.label) + '</strong><small>' + escapeHtml(size.group) + '</small></span>'
    )).join("") || '<span class="muted">لا توجد مقاسات مرجعية.</span>';

    document.getElementById("mediaColorGroups").innerHTML = colors.length
      ? colors.map(color => {
          const rows = mediaRows.filter(x => String(x.color_id || "") === String(color.id));
          const bg = color.hex_code || "#111827";
          return '<article class="color-media-card">' +
            '<div class="color-media-head"><div class="manage-card-title"><span class="color-swatch" style="background:' + escapeHtml(bg) + '"></span><div><strong>' + escapeHtml(color.name) + '</strong><small>' + rows.length + ' صورة</small></div></div></div>' +
            '<div class="media-card-grid">' + (rows.length ? rows.map(mediaCard).join("") : '<div class="media-empty">لم تُرفع صور لهذا اللون بعد.</div>') + '</div>' +
            '<div class="color-media-upload">' +
              '<input type="file" accept="image/*" multiple data-color-media-input="' + color.id + '">' +
              '<button type="button" class="primary-button" data-upload-color-media="' + color.id + '">رفع صور ' + escapeHtml(color.name) + '</button>' +
            '</div>' +
          '</article>';
        }).join("")
      : '<div class="empty-state compact"><strong>أضف لونًا أولًا.</strong><span class="muted">بعد إضافة اللون ستظهر له بطاقة رفع الصور هنا.</span></div>';

    const variantSelect = document.getElementById("inventoryVariant");
    variantSelect.innerHTML = (snapshot.variants || []).map(x => '<option value="' + x.id + '">' + escapeHtml(x.sku) + '</option>').join("");
    const locationSelect = document.getElementById("inventoryLocation");
    locationSelect.innerHTML = (snapshot.locations || []).map(x => '<option value="' + x.id + '">' + escapeHtml(x.name) + ' · ' + escapeHtml(x.code) + '</option>').join("");
    document.getElementById("inventoryList").innerHTML = (snapshot.inventory || []).map(x => (
      '<div class="stack-row"><strong>Variant #' + x.variant_id + '</strong><span>المتاح ' + x.available + ' · الفعلي ' + x.on_hand + ' · محجوز ' + x.reserved + '</span></div>'
    )).join("");

    document.getElementById("showRating").checked = snapshot.display?.show_rating ?? true;
    document.getElementById("showSoldBadge").checked = snapshot.display?.show_sold_badge ?? true;
    document.getElementById("showShipping").checked = snapshot.display?.show_shipping_banner ?? true;
    document.getElementById("showReturn").checked = snapshot.display?.show_return ?? true;

    const fillPolicies = (id, rows, selected) => {
      const select = document.getElementById(id);
      select.innerHTML = '<option value="">بدون سياسة</option>' + rows.map(x => '<option value="' + x.id + '">' + escapeHtml(x.name) + '</option>').join("");
      if (selected) select.value = String(selected);
    };
    fillPolicies("shippingPolicyId", policyRefs?.shipping || [], snapshot.policies?.shipping_policy_id);
    fillPolicies("returnPolicyId", policyRefs?.return || [], snapshot.policies?.return_policy_id);
    fillPolicies("warrantyPolicyId", policyRefs?.warranty || [], snapshot.policies?.warranty_policy_id);

    const steps = {
      basics: snapshot.steps.basics,
      categories: snapshot.steps.categories,
      media: snapshot.steps.media,
      options: snapshot.steps.options,
      variants: snapshot.steps.variants,
      inventory: snapshot.steps.inventory,
      publish: snapshot.steps.publish,
    };
    document.querySelector("[data-panel='publish'] .checklist").innerHTML = [
      ["الأساس", steps.basics],
      ["التصنيفات", steps.categories],
      ["الوسائط", steps.media],
      ["الخيارات", steps.options],
      ["المتغيرات", steps.variants],
      ["المخزون", steps.inventory],
      ["جاهز للنشر", snapshot.publishable],
    ].map(([label, ok]) => '<div class="checklist-row"><span class="' + (ok ? "ok" : "pending") + '">' + (ok ? "✓" : "•") + '</span><strong>' + label + '</strong><small>' + (ok ? "مكتمل" : "يحتاج إعدادًا") + '</small></div>').join("");
    const brand = document.getElementById("productBrand");
    brand.innerHTML = '<option value="">بدون علامة تجارية</option>' +
      (marketingRefs?.brands || []).map(x => '<option value="' + x.id + '">' + escapeHtml(x.name) + '</option>').join("");
    if (snapshot.product?.brand_id) brand.value = String(snapshot.product.brand_id);

    const activeColorOptions = (optionRefs?.colors || []).map(x =>
      '<option value="' + x.id + '"' + (!x.is_active ? ' disabled' : '') + '>' +
      escapeHtml(x.name) + (!x.is_active ? ' · مؤرشف (استعده من الأرشيف)' : '') + '</option>'
    ).join("");
    const activeSizeOptions = (optionRefs?.sizes || []).map(x =>
      '<option value="' + x.id + '"' + (!x.is_active ? ' disabled' : '') + '>' +
      escapeHtml(x.label) + ' · ' + escapeHtml(x.group) + (!x.is_active ? ' · مؤرشف' : '') + '</option>'
    ).join("");

    const color = document.getElementById("variantColor");
    color.innerHTML = '<option value="">بدون لون</option>' + activeColorOptions;
    document.querySelectorAll(".variant-edit-form").forEach(form => {
      const colorSelect = form.querySelector('select[name="color_id"]');
      const sizeSelect = form.querySelector('select[name="size_id"]');
      colorSelect.innerHTML = '<option value="">بدون لون</option>' + activeColorOptions;
      sizeSelect.innerHTML = '<option value="">بدون مقاس</option>' + activeSizeOptions;
      if (colorSelect.dataset.current) {
        colorSelect.value = colorSelect.dataset.current;
      }
      if (sizeSelect.dataset.current) {
        sizeSelect.value = sizeSelect.dataset.current;
      }
      if (colorSelect.dataset.current && !colorSelect.value) {
        colorSelect.insertAdjacentHTML("beforeend", '<option value="' + colorSelect.dataset.current + '">لون حالي مؤرشف</option>');
        colorSelect.value = colorSelect.dataset.current;
      }
      if (sizeSelect.dataset.current && !sizeSelect.value) {
        sizeSelect.insertAdjacentHTML("beforeend", '<option value="' + sizeSelect.dataset.current + '">مقاس حالي مؤرشف</option>');
        sizeSelect.value = sizeSelect.dataset.current;
      }
    });

    const mediaColor = document.getElementById("mediaColor");
    if (mediaColor) {
      mediaColor.innerHTML = '<option value="">صور عامة للمنتج</option>' +
        (optionRefs?.colors || []).map(x =>
          '<option value="' + x.id + '"' + (!x.is_active ? ' disabled' : '') + '>' +
          escapeHtml(x.name) + (!x.is_active ? ' · مؤرشف' : '') + '</option>'
        ).join("");
    }
    const size = document.getElementById("variantSize");
    size.innerHTML = '<option value="">بدون مقاس</option>' + activeSizeOptions;

    document.getElementById("badgeSelection").innerHTML = (marketingRefs?.badges || []).map(x => (
      '<label class="check-row"><input type="checkbox" value="' + x.id + '" data-badge-checkbox><span><strong>' +
      escapeHtml(x.name) + '</strong><small>' + escapeHtml(x.code) + '</small></span></label>'
    )).join("");
    const selectedBadges = new Set((snapshot.badges || []).map(x => String(x.id)));
    document.querySelectorAll("[data-badge-checkbox]").forEach(input => input.checked = selectedBadges.has(input.value));

    document.getElementById("hashtagSelection").innerHTML = (marketingRefs?.hashtags || []).map(x => (
      '<label class="check-row"><input type="checkbox" value="' + x.id + '" data-hashtag-checkbox><span><strong>' +
      escapeHtml(x.display_name || x.name) + '</strong><small>#' + escapeHtml(x.slug) + '</small></span></label>'
    )).join("");
    const selectedHashtags = new Set((snapshot.hashtags || []).map(x => String(x.id)));
    document.querySelectorAll("[data-hashtag-checkbox]").forEach(input => input.checked = selectedHashtags.has(input.value));

    document.getElementById("publishProduct").disabled = !snapshot.publishable;
  };

  const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({
    "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"
  }[char]));

  const activate = (key) => {
    panels.forEach(panel => {
      const active = panel.dataset.panel === key;
      panel.classList.toggle("is-active", active);
      panel.hidden = !active;
    });
    steps.forEach(step => step.classList.toggle("is-active", step.dataset.step === key));
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  steps.forEach(step => step.addEventListener("click", () => activate(step.dataset.step)));

  const closeModal = (name) => {
    const modal = document.querySelector('[data-modal="' + name + '"]');
    if (modal) modal.hidden = true;
    document.body.classList.remove("modal-open");
  };

  document.getElementById("productColors").addEventListener("click", (event) => {
    const button = event.target.closest("[data-use-color]");
    if (!button) return;
    const select = document.getElementById("variantColor");
    select.value = button.dataset.useColor;
    activate("variants");
    select.focus();
  });

  document.getElementById("mediaColorGroups").addEventListener("click", async (event) => {
    const deleteButton = event.target.closest("[data-delete-media]");
    if (deleteButton) {
      try {
        await requestJson("/api/v1/catalog/products/" + productId + "/media/" + deleteButton.dataset.deleteMedia, { method: "DELETE" });
        await load();
        notify("تم حذف الصورة.");
      } catch (error) { notify(error.message, "error"); }
      return;
    }

    const button = event.target.closest("[data-upload-color-media]");
    if (!button) return;
    const input = document.querySelector('[data-color-media-input="' + button.dataset.uploadColorMedia + '"]');
    if (!input || !input.files.length) {
      notify("اختر صورة واحدة على الأقل لهذا اللون.", "error");
      return;
    }
    const body = new FormData();
    [...input.files].forEach(file => body.append("files", file));
    body.append("color_id", button.dataset.uploadColorMedia);
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/media", { method: "POST", body });
      input.value = "";
      await load();
      notify("تم رفع صور اللون بنجاح.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("quickColorForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      const created = await requestJson("/api/v1/catalog/reference/colors", {
        method: "POST",
        body: JSON.stringify({
          name: form.get("name"),
          hex_code: form.get("hex_code"),
          sort_order: Number(form.get("sort_order") || 0),
        }),
      });
      closeModal("quickColorModal");
      event.currentTarget.reset();
      await load();
      const select = document.getElementById("variantColor");
      if (created.item?.id) {
        select.value = String(created.item.id);
        activate("variants");
      }
      notify("تم إنشاء اللون وإضافته لقائمة المتغيرات.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("quickSizeForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      await requestJson("/api/v1/catalog/reference/sizes", {
        method: "POST",
        body: JSON.stringify({
          group: form.get("group"),
          code: form.get("code"),
          label: form.get("label"),
          sort_order: Number(form.get("sort_order") || 0),
        }),
      });
      closeModal("quickSizeModal");
      event.currentTarget.reset();
      await load();
      notify("تم إنشاء المقاس وتحديث القائمة.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("quickBadgeForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      const created = await requestJson("/api/v1/catalog/badges", {
        method: "POST",
        body: JSON.stringify({
          name: form.get("name"),
          code: form.get("code"),
          bg_color: form.get("bg_color"),
          text_color: form.get("text_color"),
          style: form.get("style"),
          priority: Number(form.get("priority") || 0),
        }),
      });
      closeModal("quickBadgeModal");
      event.currentTarget.reset();
      await load();
      const checkbox = document.querySelector('[data-badge-checkbox][value="' + created.item?.id + '"]');
      if (checkbox) {
        checkbox.checked = true;
      }
      notify("تم إنشاء الشارة وتحديث القائمة.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("basicsForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const body = {
      sku: document.getElementById("productSku").value.trim(),
      name: document.getElementById("productName").value.trim(),
      description: document.getElementById("productDescription").value,
      slug: document.getElementById("productSlug").value.trim(),
      base_price: document.getElementById("productPrice").value,
      material: document.getElementById("productMaterial").value,
      care_instructions: document.getElementById("productCare").value,
      compare_at_price: document.getElementById("productCompareAtPrice").value || null,
      brand_id: document.getElementById("productBrand").value || null,
      product_type: document.getElementById("productType").value,
    };
    try {
      await requestJson("/api/v1/catalog/products/" + productId, { method: "PATCH", body: JSON.stringify(body) });
      await load();
      notify("تم حفظ البيانات الأساسية.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("saveCategories").addEventListener("click", async () => {
    const categoryIds = [...document.querySelectorAll("[data-category-checkbox]:checked")].map(input => Number(input.value));
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/categories", { method: "POST", body: JSON.stringify({ category_ids: categoryIds }) });
      await load();
      notify("تم حفظ التصنيفات.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("mediaPreview").addEventListener("click", async (event) => {
    const button = event.target.closest("[data-delete-media]");
    if (!button) return;
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/media/" + button.dataset.deleteMedia, { method: "DELETE" });
      await load();
      notify("تم حذف الصورة.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("uploadMedia").addEventListener("click", async () => {
    const input = document.getElementById("productMedia");
    if (!input.files.length) return notify("اختر صورة واحدة على الأقل.", "error");
    const body = new FormData();
    [...input.files].forEach(file => body.append("files", file));
    const mediaColor = document.getElementById("mediaColor");
    if (mediaColor?.value) body.append("color_id", mediaColor.value);
    try {
      const response = await fetch("/api/v1/catalog/products/" + productId + "/media", { method: "POST", body });
      const data = await response.json();
      if (!response.ok) throw new Error(data.detail || data.error || "فشل رفع الصور");
      input.value = "";
      await load();
      notify("تم رفع الصور وتحسين أحجامها.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("optionForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const values = String(form.get("values_text") || "").split("\n").map(x => x.trim()).filter(Boolean).map(label => ({ label }));
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/options", {
        method: "POST",
        body: JSON.stringify({
          name: form.get("name"),
          option_type: form.get("option_type"),
          required: form.get("required") === "on",
          values,
        }),
      });
      event.currentTarget.reset();
      await load();
      notify("تمت إضافة الخيار وقيمه.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("saveMarketing").addEventListener("click", async () => {
    const badgeIds = [...document.querySelectorAll("[data-badge-checkbox]:checked")].map(input => Number(input.value));
    const hashtagIds = [...document.querySelectorAll("[data-hashtag-checkbox]:checked")].map(input => Number(input.value));
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/badges", {
        method: "POST",
        body: JSON.stringify({ badge_ids: badgeIds }),
      });
      await requestJson("/api/v1/catalog/products/" + productId + "/hashtags", {
        method: "POST",
        body: JSON.stringify({ hashtag_ids: hashtagIds }),
      });
      await load();
      notify("تم حفظ الشارات والهاشتاجات.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("variantForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/variants", {
        method: "POST",
        body: JSON.stringify({
          sku: form.get("sku"),
          color_id: form.get("color_id") ? Number(form.get("color_id")) : null,
          size_id: form.get("size_id") ? Number(form.get("size_id")) : null,
          barcode: form.get("barcode"),
          weight: form.get("weight") || null,
        }),
      });
      event.currentTarget.reset();
      await load();
      notify("تمت إضافة الـVariant.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("inventoryForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/inventory", {
        method: "POST",
        body: JSON.stringify({
          variant_id: Number(form.get("variant_id")),
          location_id: Number(form.get("location_id")),
          on_hand: Number(form.get("on_hand")),
          reserved: Number(form.get("reserved")),
          reorder_level: Number(form.get("reorder_level")),
        }),
      });
      await load();
      notify("تم حفظ المخزون.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("locationForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      await requestJson("/api/v1/catalog/inventory-locations", {
        method: "POST",
        body: JSON.stringify({
          name: form.get("name"),
          code: form.get("code"),
          city_id: form.get("city_id") ? Number(form.get("city_id")) : null,
        }),
      });
      event.currentTarget.reset();
      await load();
      notify("تم إنشاء موقع التخزين.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("saveDisplay").addEventListener("click", async () => {
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/display-settings", {
        method: "POST",
        body: JSON.stringify({
          show_rating: document.getElementById("showRating").checked,
          show_sold_badge: document.getElementById("showSoldBadge").checked,
          show_shipping_banner: document.getElementById("showShipping").checked,
          show_return: document.getElementById("showReturn").checked,
        }),
      });
      const policies = {};
      for (const [key, id] of [
        ["shipping_policy_id", "shippingPolicyId"],
        ["return_policy_id", "returnPolicyId"],
        ["warranty_policy_id", "warrantyPolicyId"],
      ]) {
        const value = document.getElementById(id).value;
        if (value) policies[key] = Number(value);
      }
      await requestJson("/api/v1/catalog/products/" + productId + "/policies", {
        method: "POST",
        body: JSON.stringify(policies),
      });
      await load();
      notify("تم حفظ العرض والسياسات.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("publishProduct").addEventListener("click", async () => {
    if (!snapshot?.publishable) return;
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/publish", { method: "POST", body: "{}" });
      await load();
      notify("تم نشر المنتج.");
    } catch (error) { notify(error.message, "error"); }
  });

  load();
})();

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
        requestJson("/api/v1/catalog/reference/options"),
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
      '<div class="stack-row"><strong>' + escapeHtml(option.name) + '</strong><span>' +
      (option.values || []).map(v => escapeHtml(v.label)).join(" · ") +
      '</span></div>'
    )).join("");

    document.getElementById("variantsList").innerHTML = (snapshot.variants || []).map(variant => (
      '<div class="stack-row"><strong>' + escapeHtml(variant.sku) + '</strong><span>' +
      'Color: ' + (variant.color_id || "—") + ' · Size: ' + (variant.size_id || "—") +
      '</span></div>'
    )).join("");

    const mediaRows = snapshot.media || [];
    document.getElementById("mediaPreview").innerHTML = mediaRows.map(item => (
      '<div class="media-thumb">' +
      (item.url ? '<img src="' + escapeHtml(item.url) + '" alt="" style="width:100%;height:100%;object-fit:cover;border-radius:12px">' : '<span>صورة</span>') +
      '<small>' + (item.color_name ? escapeHtml(item.color_name) : 'عام') + ' · #' + item.id + '</small>' +
      '<button type="button" class="ghost-button" data-delete-media="' + item.id + '">حذف</button></div>'
    )).join("");
    document.getElementById("mediaColorGroups").innerHTML = (optionRefs?.colors || []).map(color => {
      const rows = mediaRows.filter(x => String(x.color_id || "") === String(color.id));
      return rows.length ? '<div class="stack-row"><strong>' + escapeHtml(color.name) + '</strong><span>' + rows.length + ' صورة</span></div>' : '';
    }).join("");

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

    const color = document.getElementById("variantColor");
    color.innerHTML = '<option value="">بدون لون</option>' +
      (optionRefs?.colors || []).map(x => '<option value="' + x.id + '">' + escapeHtml(x.name) + '</option>').join("");
    const mediaColor = document.getElementById("mediaColor");
    if (mediaColor) {
      mediaColor.innerHTML = '<option value="">صور عامة للمنتج</option>' +
        (optionRefs?.colors || []).map(x => '<option value="' + x.id + '">' + escapeHtml(x.name) + '</option>').join("");
    }
    const size = document.getElementById("variantSize");
    size.innerHTML = '<option value="">بدون مقاس</option>' +
      (optionRefs?.sizes || []).map(x => '<option value="' + x.id + '">' + escapeHtml(x.label) + ' · ' + escapeHtml(x.group) + '</option>').join("");

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

  const slugInput = document.getElementById("productSlug");
  const nameInput = document.getElementById("productName");
  let slugTouched = Boolean(slugInput?.value.trim());
  slugInput?.addEventListener("input", () => { slugTouched = true; });
  nameInput?.addEventListener("input", () => {
    if (!slugTouched && slugInput) slugInput.value = String(nameInput.value || "").toLowerCase().trim()
      .normalize("NFKD").replace(/[\u064B-\u065F\u0670]/g, "")
      .replace(/[أإآ]/g, "a").replace(/ة/g, "h").replace(/ى/g, "a")
      .replace(/[ءؤئ]/g, "a").replace(/[ابتثجحخدذرزسشصضطظعغفقكلمنهوي]/g, ch => ch)
      .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 220);
  });
  steps.forEach(step => step.addEventListener("click", () => activate(step.dataset.step)));

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

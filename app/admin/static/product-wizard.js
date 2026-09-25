(() => {
  const shell = document.querySelector(".wizard-shell");
  if (!shell) return;

  const productId = shell.dataset.productId;
  const message = document.getElementById("wizardMessage");
  const panels = [...document.querySelectorAll(".wizard-panel")];
  const steps = [...document.querySelectorAll(".wizard-step")];
  const seedElement = document.getElementById("wizardReferenceSeed");
  let snapshot = null;
  let policyRefs = null;
  let marketingRefs = null;
  let optionRefs = null;
  let configRefs = (() => {
    try {
      return JSON.parse(seedElement?.textContent || "{}") || {};
    } catch (error) {
      return {};
    }
  })();
  let draftColorIds = new Set();
  let draftSizeIds = new Set();
  let draftCategoryIds = new Set();
  let draftsInitialized = false;

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
    const requests = await Promise.allSettled([
      requestJson("/api/v1/catalog/products/" + productId + "/wizard"),
      requestJson("/api/v1/catalog/reference/policies"),
      requestJson("/api/v1/catalog/reference/marketing"),
      requestJson("/api/v1/catalog/reference/options?product_id=" + encodeURIComponent(productId)),
      requestJson("/api/v1/catalog/reference/product-config?product_id=" + encodeURIComponent(productId)),
    ]);

    const [result, refs, marketing, options, config] = requests;
    if (result.status === "rejected") {
      notify(result.reason?.message || "تعذر تحميل بيانات المنتج.", "error");
      return;
    }

    snapshot = result.value.item;
    if (refs.status === "fulfilled") policyRefs = refs.value;
    if (marketing.status === "fulfilled") marketingRefs = marketing.value;
    if (options.status === "fulfilled") optionRefs = options.value.item || options.value;
    if (config.status === "fulfilled") {
      configRefs = { ...(configRefs || {}), ...(config.value.item || config.value) };
    }

    hydrate();

    const optionalFailures = requests.slice(1).filter(item => item.status === "rejected");
    if (optionalFailures.length && !configRefs?.categories?.length && !configRefs?.colors?.length) {
      notify("تم تحميل المنتج، لكن تعذر تحميل بعض مراجع الكتالوج. أعد تحميل الصفحة للمحاولة مرة أخرى.", "error");
    }
  };

  const renderCategoryTree = (rows, selectedIds) => {
    const query = (document.getElementById("categorySearch")?.value || "").trim().toLocaleLowerCase();
    const byParent = new Map();
    rows.forEach(row => {
      const key = row.parent_id == null ? null : Number(row.parent_id);
      if (!byParent.has(key)) byParent.set(key, []);
      byParent.get(key).push(row);
    });
    byParent.forEach(list => list.sort((a, b) =>
      (a.sort_order ?? 0) - (b.sort_order ?? 0) ||
      String(a.name).localeCompare(String(b.name), "ar")
    ));

    const matches = row =>
      !query ||
      String(row.name).toLocaleLowerCase().includes(query) ||
      String(row.slug).toLocaleLowerCase().includes(query);

    const hasMatchingDescendant = (row, trail = new Set()) => {
      if (trail.has(row.id)) return false;
      const nextTrail = new Set(trail);
      nextTrail.add(row.id);
      return (byParent.get(row.id) || []).some(child =>
        matches(child) || hasMatchingDescendant(child, nextTrail)
      );
    };

    const walk = (parentId, depth = 0, trail = new Set()) => {
      const rowsAtLevel = byParent.get(parentId) || [];
      return rowsAtLevel.map(category => {
        if (trail.has(category.id)) return "";
        const include = !query || matches(category) || hasMatchingDescendant(category);
        if (!include) return "";
        const nextTrail = new Set(trail);
        nextTrail.add(category.id);
        const children = walk(category.id, depth + 1, nextTrail);
        const hasChildren = Boolean(children);
        return '<div class="category-picker-node" style="--depth:' + depth + '">' +
          '<label class="category-picker-choice">' +
          '<input type="checkbox" value="' + category.id + '" data-category-checkbox ' +
            (selectedIds.has(String(category.id)) ? 'checked' : '') +
            (category.is_active ? '' : ' disabled') + '>' +
          '<span class="category-picker-marker">' + (hasChildren ? "▾" : "•") + '</span>' +
          '<span class="category-picker-copy"><strong>' + escapeHtml(category.name) + '</strong><small>' +
            escapeHtml(category.slug) + (!category.is_active ? ' · مؤرشف' : '') +
          '</small></span></label>' + children + '</div>';
      }).join("");
    };
    const tree = walk(null);
    return tree || '<div class="empty-state compact"><strong>لا توجد نتائج.</strong><span class="muted">عدّل كلمة البحث أو أضف تصنيفًا جديدًا.</span></div>';
  };

  const renderDimensionChoices = () => {
    const colors = (configRefs?.colors || []).slice();
    const sizes = (configRefs?.sizes || []).slice();
    const colorQuery = (document.getElementById("colorSearch")?.value || "").trim().toLocaleLowerCase();
    const sizeQuery = (document.getElementById("sizeSearch")?.value || "").trim().toLocaleLowerCase();

    const matchingColors = colors.filter(color =>
      !colorQuery || String(color.name).toLocaleLowerCase().includes(colorQuery)
    );
    const matchingSizes = sizes.filter(size =>
      !sizeQuery ||
      String(size.label).toLocaleLowerCase().includes(sizeQuery) ||
      String(size.code).toLocaleLowerCase().includes(sizeQuery) ||
      String(size.group).toLocaleLowerCase().includes(sizeQuery)
    );

    document.getElementById("productColors").innerHTML = matchingColors.length
      ? matchingColors.map(color => {
          const checked = draftColorIds.has(Number(color.id));
          return '<label class="reference-choice-card ' + (checked ? "is-selected" : "") + (!color.is_active ? " is-archived" : "") + '">' +
            '<input type="checkbox" value="' + color.id + '" data-color-ref-checkbox ' +
              (checked ? 'checked' : '') + (color.is_active ? '' : ' disabled') + '>' +
            '<span class="color-swatch large" style="background:' + escapeHtml(color.hex_code || "#111827") + '"></span>' +
            '<span class="reference-choice-copy"><strong>' + escapeHtml(color.name) + '</strong><small>' +
              (color.is_active ? (checked ? "متاح لهذا المنتج" : "متاح للاختيار") : "مؤرشف — أعده من جدول الألوان") +
            '</small></span><span class="reference-choice-check">' + (checked ? "✓" : "○") + '</span></label>';
        }).join("")
      : '<div class="empty-state compact"><strong>لا توجد ألوان مطابقة.</strong><span class="muted">ابحث باسم آخر أو أضف لونًا جديدًا من الزر.</span></div>';

    document.getElementById("sizeReferencePreview").innerHTML = matchingSizes.length
      ? matchingSizes.map(size => {
          const checked = draftSizeIds.has(Number(size.id));
          return '<label class="reference-choice-card ' + (checked ? "is-selected" : "") + (!size.is_active ? " is-archived" : "") + '">' +
            '<input type="checkbox" value="' + size.id + '" data-size-ref-checkbox ' +
              (checked ? 'checked' : '') + (size.is_active ? '' : ' disabled') + '>' +
            '<span class="size-choice-badge">' + escapeHtml(size.code) + '</span>' +
            '<span class="reference-choice-copy"><strong>' + escapeHtml(size.label) + '</strong><small>' +
              escapeHtml(size.group) + (!size.is_active ? ' · مؤرشف' : '') +
            '</small></span><span class="reference-choice-check">' + (checked ? "✓" : "○") + '</span></label>';
        }).join("")
      : '<div class="empty-state compact"><strong>لا توجد مقاسات مطابقة.</strong><span class="muted">ابحث باسم أو كود آخر أو أضف مقاسًا جديدًا.</span></div>';

    document.getElementById("productColorCount").textContent = draftColorIds.size + " محدد";
    document.getElementById("availableSizeCount").textContent = draftSizeIds.size + " محدد";
    const colorSummary = document.getElementById("colorSelectionSummary");
    const sizeSummary = document.getElementById("sizeSelectionSummary");
    if (colorSummary) colorSummary.textContent = draftColorIds.size + " محدد";
    if (sizeSummary) sizeSummary.textContent = draftSizeIds.size + " محدد";
  };

  const syncVariantSelectors = () => {
    const colors = (configRefs?.colors || optionRefs?.colors || []).filter(x =>
      x.is_active && draftColorIds.has(Number(x.id))
    );
    const sizes = (configRefs?.sizes || optionRefs?.sizes || []).filter(x =>
      x.is_active && draftSizeIds.has(Number(x.id))
    );

    const colorOptions = colors.map(x => '<option value="' + x.id + '">' + escapeHtml(x.name) + '</option>').join("");
    const sizeOptions = sizes.map(x => '<option value="' + x.id + '">' + escapeHtml(x.label) + ' · ' + escapeHtml(x.group) + '</option>').join("");

    const colorSelect = document.getElementById("variantColor");
    const sizeSelect = document.getElementById("variantSize");
    if (colorSelect) {
      const current = colorSelect.value;
      colorSelect.innerHTML = '<option value="">' + (colors.length ? "اختر اللون" : "لا توجد ألوان مختارة — اذهب إلى خطوة الألوان") + '</option>' + colorOptions;
      if (current && colors.some(x => String(x.id) === current)) colorSelect.value = current;
    }
    if (sizeSelect) {
      const current = sizeSelect.value;
      sizeSelect.innerHTML = '<option value="">' + (sizes.length ? "اختر المقاس" : "لا توجد مقاسات مختارة — اذهب إلى خطوة المقاسات") + '</option>' + sizeOptions;
      if (current && sizes.some(x => String(x.id) === current)) sizeSelect.value = current;
    }
  };

  const hydrate = () => {
    const categories = configRefs?.categories || [];
    const categoryParent = document.querySelector('#quickCategoryForm select[name="parent_id"]');
    if (categoryParent) {
      categoryParent.innerHTML = '<option value="">بدون أب</option>' +
        categories.filter(x => x.is_active).map(x => '<option value="' + x.id + '">↳ ' + escapeHtml(x.name) + '</option>').join("");
    }
    if (!draftsInitialized) {
      draftCategoryIds = new Set((snapshot.categories || []).map(x => String(x.id)));
    }
    document.getElementById("categorySelection").innerHTML = renderCategoryTree(categories, draftCategoryIds);

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

    const colorMap = new Map((configRefs?.colors || optionRefs?.colors || []).map(x => [Number(x.id), x]));
    const sizeMap = new Map((configRefs?.sizes || optionRefs?.sizes || []).map(x => [Number(x.id), x]));
    document.getElementById("variantsList").innerHTML = (snapshot.variants || []).map(variant => (
      '<details class="panel" style="padding:12px">' +
      '<summary><strong>' + escapeHtml(variant.sku) + '</strong><span class="muted"> · اللون: ' +
        escapeHtml(colorMap.get(Number(variant.color_id))?.name || "بدون لون") + ' · المقاس: ' +
        escapeHtml(sizeMap.get(Number(variant.size_id))?.label || "بدون مقاس") + '</span></summary>' +
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

    configRefs = configRefs || optionRefs || {};
    if (!draftsInitialized) {
      draftCategoryIds = new Set((snapshot.categories || []).map(x => String(x.id)));
      draftColorIds = new Set((snapshot.reference_colors || []).map(x => Number(x.id)));
      draftSizeIds = new Set((snapshot.reference_sizes || []).map(x => Number(x.id)));
      if (!draftColorIds.size) {
        draftColorIds = new Set((configRefs.colors || []).filter(x => x.selected).map(x => Number(x.id)));
      }
      if (!draftSizeIds.size) {
        draftSizeIds = new Set((configRefs.sizes || []).filter(x => x.selected).map(x => Number(x.id)));
      }
      draftsInitialized = true;
    }
    renderDimensionChoices();

    const mediaColors = (configRefs?.colors || optionRefs?.colors || []).filter(color =>
      color.is_active && (draftColorIds.has(Number(color.id)) || mediaRows.some(x => Number(x.color_id) === Number(color.id)))
    );
    document.getElementById("mediaColorGroups").innerHTML = mediaColors.length
      ? mediaColors.map(color => {
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
    const variantMap = new Map((snapshot.variants || []).map(x => [Number(x.id), x]));
    document.getElementById("inventoryList").innerHTML = (snapshot.inventory || []).map(x => {
      const variant = variantMap.get(Number(x.variant_id));
      return '<div class="stack-row"><strong>' + escapeHtml(variant?.sku || ("Variant #" + x.variant_id)) +
        '</strong><span>المتاح ' + x.available + ' · الفعلي ' + x.on_hand + ' · محجوز ' + x.reserved + '</span></div>';
    }).join("");

    document.getElementById("showRating").checked = snapshot.display?.show_rating ?? true;
    document.getElementById("showSoldBadge").checked = snapshot.display?.show_sold_badge ?? true;
    document.getElementById("showShipping").checked = snapshot.display?.show_shipping_banner ?? true;
    document.getElementById("showReturn").checked = snapshot.display?.show_return ?? true;

    const fillPolicies = (id, rows, selected) => {
      const select = document.getElementById(id);
      select.innerHTML = '<option value="">بدون سياسة</option>' +
        rows.map(x => '<option value="' + x.id + '"' + (!x.is_active ? ' disabled' : '') + '>' +
          escapeHtml(x.name) + (x.summary ? ' · ' + escapeHtml(x.summary) : '') +
          (!x.is_active ? ' · مؤرشف' : '') + '</option>').join("");
      if (selected) select.value = String(selected);
    };
    const referencePolicies = configRefs?.policies || policyRefs || {};
    fillPolicies("shippingPolicyId", referencePolicies.shipping || [], snapshot.policies?.shipping_policy_id);
    fillPolicies("returnPolicyId", referencePolicies.return || [], snapshot.policies?.return_policy_id);
    fillPolicies("warrantyPolicyId", referencePolicies.warranty || [], snapshot.policies?.warranty_policy_id);

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
    const campaignBadgeSelect = document.getElementById("campaignBadgeId");
    if (campaignBadgeSelect) {
      campaignBadgeSelect.innerHTML = '<option value="">بدون شارة</option>' +
        (configRefs?.badges || []).filter(x => x.is_active).map(x => '<option value="' + x.id + '">' + escapeHtml(x.name) + '</option>').join("");
    }

    const brand = document.getElementById("productBrand");
    const brands = configRefs?.brands || marketingRefs?.brands || [];
    brand.innerHTML = '<option value="">بدون علامة تجارية</option>' +
      brands.map(x => '<option value="' + x.id + '"' + (!x.is_active ? ' disabled' : '') + '>' +
        escapeHtml(x.name) + (!x.is_active ? ' · مؤرشف' : '') + '</option>').join("");
    if (snapshot.product?.brand_id) brand.value = String(snapshot.product.brand_id);

    syncVariantSelectors();
    document.querySelectorAll(".variant-edit-form").forEach(form => {
      const colorSelect = form.querySelector('select[name="color_id"]');
      const sizeSelect = form.querySelector('select[name="size_id"]');
      const currentColor = colorSelect.dataset.current || "";
      const currentSize = sizeSelect.dataset.current || "";
      const colors = (configRefs?.colors || optionRefs?.colors || []).filter(x => x.is_active || Number(x.id) === Number(currentColor));
      const sizes = (configRefs?.sizes || optionRefs?.sizes || []).filter(x => x.is_active || Number(x.id) === Number(currentSize));
      colorSelect.innerHTML = '<option value="">بدون لون</option>' + colors.map(x =>
        '<option value="' + x.id + '"' + (!x.is_active ? ' disabled' : '') + '>' +
        escapeHtml(x.name) + (!x.is_active ? ' · مؤرشف' : '') + '</option>'
      ).join("");
      sizeSelect.innerHTML = '<option value="">بدون مقاس</option>' + sizes.map(x =>
        '<option value="' + x.id + '"' + (!x.is_active ? ' disabled' : '') + '>' +
        escapeHtml(x.label) + ' · ' + escapeHtml(x.group) + (!x.is_active ? ' · مؤرشف' : '') + '</option>'
      ).join("");
      if (currentColor) colorSelect.value = currentColor;
      if (currentSize) sizeSelect.value = currentSize;
    });

    const mediaColor = document.getElementById("mediaColor");
    if (mediaColor) {
      const mediaColors = (configRefs?.colors || optionRefs?.colors || []).filter(x => x.is_active && (draftColorIds.has(Number(x.id)) || (snapshot.media || []).some(m => Number(m.color_id) === Number(x.id))));
      mediaColor.innerHTML = '<option value="">صور عامة للمنتج</option>' +
        mediaColors.map(x => '<option value="' + x.id + '">' + escapeHtml(x.name) + '</option>').join("");
    }
    const selectedBadges = new Set((snapshot.badges || []).map(x => String(x.id)));
    const selectedHashtags = new Set((snapshot.hashtags || []).map(x => String(x.id)));
    const selectedStrips = new Set((snapshot.promotional_strips || []).map(x => String(x.id)));
    const selectedCampaigns = new Set((snapshot.campaigns || []).map(x => String(x.id)));
    const marketing = configRefs || marketingRefs || {};

    document.getElementById("badgeSelection").innerHTML = (marketing.badges || []).map(x => (
      '<label class="check-row"><input type="checkbox" value="' + x.id + '" data-badge-checkbox ' +
        (selectedBadges.has(String(x.id)) ? 'checked' : '') + (!x.is_active ? ' disabled' : '') + '><span><strong>' +
      escapeHtml(x.name) + '</strong><small>' + escapeHtml(x.code) + (!x.is_active ? ' · مؤرشف' : '') + '</small></span></label>'
    )).join("") || '<div class="empty-state compact"><strong>لا توجد شارات.</strong><span class="muted">أضف شارة جديدة من الزر.</span></div>';

    document.getElementById("hashtagSelection").innerHTML = (marketing.hashtags || []).map(x => (
      '<label class="check-row"><input type="checkbox" value="' + x.id + '" data-hashtag-checkbox ' +
        (selectedHashtags.has(String(x.id)) ? 'checked' : '') + (!x.is_active ? ' disabled' : '') + '><span><strong>' +
      escapeHtml(x.display_name || x.name) + '</strong><small>#' + escapeHtml(x.slug) + (!x.is_active ? ' · مؤرشف' : '') + '</small></span></label>'
    )).join("") || '<div class="empty-state compact"><strong>لا توجد هاشتاجات.</strong><span class="muted">أضف هاشتاجًا جديدًا من الزر.</span></div>';

    document.getElementById("stripSelection").innerHTML = (marketing.promotional_strips || []).map(x => (
      '<label class="check-row"><input type="checkbox" value="' + x.id + '" data-strip-checkbox ' +
        (selectedStrips.has(String(x.id)) ? 'checked' : '') + (!x.is_active ? ' disabled' : '') + '><span><strong>' +
      escapeHtml(x.name) + '</strong><small>' + escapeHtml(x.text_body || '') + (!x.is_active ? ' · مؤرشف' : '') + '</small></span></label>'
    )).join("") || '<div class="empty-state compact"><strong>لا توجد شرائط عروض.</strong><span class="muted">أضف شريطًا جديدًا من الزر.</span></div>';

    document.getElementById("campaignSelection").innerHTML = (marketing.campaigns || []).map(x => (
      '<label class="check-row"><input type="checkbox" value="' + x.id + '" data-campaign-checkbox ' +
        (selectedCampaigns.has(String(x.id)) ? 'checked' : '') + (!x.is_active ? ' disabled' : '') + '><span><strong>' +
      escapeHtml(x.name) + '</strong><small>' + escapeHtml(x.status || '') + (!x.is_active ? ' · مؤرشف' : '') + '</small></span></label>'
    )).join("") || '<div class="empty-state compact"><strong>لا توجد حملات.</strong><span class="muted">أضف حملة جديدة من الزر.</span></div>';

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
  document.querySelectorAll("[data-go-step]").forEach(button => {
    button.addEventListener("click", () => activate(button.dataset.goStep));
  });

  const closeModal = (name) => {
    const modal = document.querySelector('[data-modal="' + name + '"]');
    if (modal) modal.hidden = true;
    document.body.classList.remove("modal-open");
  };

  document.getElementById("categorySelection").addEventListener("change", (event) => {
    const input = event.target.closest("[data-category-checkbox]");
    if (!input) return;
    if (input.checked) draftCategoryIds.add(input.value);
    else draftCategoryIds.delete(input.value);
    input.closest(".category-picker-choice")?.classList.toggle("is-selected", input.checked);
  });

  document.getElementById("productColors").addEventListener("change", (event) => {
    const input = event.target.closest("[data-color-ref-checkbox]");
    if (!input) return;
    const id = Number(input.value);
    if (input.checked) draftColorIds.add(id);
    else draftColorIds.delete(id);
    renderDimensionChoices();
    syncVariantSelectors();
  });

  document.getElementById("sizeReferencePreview").addEventListener("change", (event) => {
    const input = event.target.closest("[data-size-ref-checkbox]");
    if (!input) return;
    const id = Number(input.value);
    if (input.checked) draftSizeIds.add(id);
    else draftSizeIds.delete(id);
    renderDimensionChoices();
    syncVariantSelectors();
  });

  const dimensionAction = (type) => {
    const rows = type.startsWith("colors")
      ? (configRefs?.colors || []).filter(x => x.is_active)
      : (configRefs?.sizes || []).filter(x => x.is_active);
    const target = type.endsWith("all");
    const set = type.startsWith("colors") ? draftColorIds : draftSizeIds;
    rows.forEach(row => target ? set.add(Number(row.id)) : set.delete(Number(row.id)));
    renderDimensionChoices();
    syncVariantSelectors();
  };

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
      if (created.item?.id) {
        const id = Number(created.item.id);
        draftColorIds.add(id);
        configRefs = configRefs || {};
        const exists = (configRefs.colors || []).some(item => Number(item.id) === id);
        if (!exists) {
          configRefs.colors = [
            ...(configRefs.colors || []),
            { ...created.item, is_active: true, selected: true },
          ];
        }
        renderDimensionChoices();
        syncVariantSelectors();
        await requestJson("/api/v1/catalog/products/" + productId + "/reference-dimensions", {
          method: "POST",
          body: JSON.stringify({ color_ids: [...draftColorIds], size_ids: [...draftSizeIds] }),
        });
        await load();
      }
      notify("تم إنشاء اللون وربطه بالمنتج مباشرة.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("quickSizeForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      const created = await requestJson("/api/v1/catalog/reference/sizes", {
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
      if (created.item?.id) {
        const id = Number(created.item.id);
        draftSizeIds.add(id);
        configRefs = configRefs || {};
        const exists = (configRefs.sizes || []).some(item => Number(item.id) === id);
        if (!exists) {
          configRefs.sizes = [
            ...(configRefs.sizes || []),
            { ...created.item, is_active: true, selected: true },
          ];
        }
        renderDimensionChoices();
        syncVariantSelectors();
        await requestJson("/api/v1/catalog/products/" + productId + "/reference-dimensions", {
          method: "POST",
          body: JSON.stringify({ color_ids: [...draftColorIds], size_ids: [...draftSizeIds] }),
        });
        await load();
      }
      notify("تم إنشاء المقاس وربطه بالمنتج مباشرة.");
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

  const submitQuickReference = async (formId, url, payloadBuilder, afterCreate, successText) => {
    const formEl = document.getElementById(formId);
    if (!formEl) return;
    formEl.addEventListener("submit", async (event) => {
      event.preventDefault();
      const form = new FormData(event.currentTarget);
      try {
        const created = await requestJson(url, {
          method: "POST",
          body: JSON.stringify(payloadBuilder(form)),
        });
        closeModal(event.currentTarget.closest(".admin-modal")?.dataset.modal);
        event.currentTarget.reset();
        await load();
        await afterCreate(created.item || {});
        notify(successText);
      } catch (error) { notify(error.message, "error"); }
    });
  };

  submitQuickReference(
    "quickBrandForm",
    "/api/v1/catalog/reference/brands",
    form => ({ name: form.get("name"), slug: form.get("slug") }),
    async item => { if (item.id) document.getElementById("productBrand").value = String(item.id); },
    "تم إنشاء العلامة وإضافتها لقائمة العلامات التجارية."
  );

  submitQuickReference(
    "quickCategoryForm",
    "/api/v1/catalog/reference/categories",
    form => ({
      name: form.get("name"), slug: form.get("slug"), parent_id: form.get("parent_id") ? Number(form.get("parent_id")) : null,
      display_style: form.get("display_style"), sort_order: Number(form.get("sort_order") || 0),
    }),
    async item => {
      if (item.id) {
        const id = Number(item.id);
        draftCategoryIds.add(String(id));
        configRefs = configRefs || {};
        const exists = (configRefs.categories || []).some(row => Number(row.id) === id);
        if (!exists) configRefs.categories = [...(configRefs.categories || []), { ...item, is_active: true }];
        document.getElementById("categorySelection").innerHTML = renderCategoryTree(configRefs.categories || [], draftCategoryIds);
        await requestJson("/api/v1/catalog/products/" + productId + "/categories", {
          method: "POST",
          body: JSON.stringify({ category_ids: [...draftCategoryIds].map(Number) }),
        });
        await load();
      }
    },
    "تم إنشاء التصنيف وإضافته إلى اختيار المنتج."
  );

  submitQuickReference(
    "quickHashtagForm",
    "/api/v1/catalog/reference/hashtags",
    form => ({
      name: form.get("name"), display_name: form.get("display_name"), slug: form.get("slug"),
      sort_order: Number(form.get("sort_order") || 0),
    }),
    async item => {
      if (item.id) {
        const input = document.querySelector('[data-hashtag-checkbox][value="' + item.id + '"]');
        if (input) input.checked = true;
      }
    },
    "تم إنشاء الهاشتاج وإضافته لقائمة المنتج."
  );

  submitQuickReference(
    "quickStripForm",
    "/api/v1/catalog/reference/promotional-strips",
    form => ({
      name: form.get("name"), text_prefix: form.get("text_prefix"), text_body: form.get("text_body"),
      background_color: form.get("background_color"), text_color: form.get("text_color"),
    }),
    async item => {
      if (item.id) {
        const input = document.querySelector('[data-strip-checkbox][value="' + item.id + '"]');
        if (input) input.checked = true;
      }
    },
    "تم إنشاء شريط العرض وإضافته لقائمة المنتج."
  );

  submitQuickReference(
    "quickCampaignForm",
    "/api/v1/catalog/reference/campaigns",
    form => ({
      name: form.get("name"), slug: form.get("slug"), badge_id: form.get("badge_id") ? Number(form.get("badge_id")) : null,
      status: form.get("status"), display_priority: Number(form.get("display_priority") || 0),
    }),
    async item => {
      if (item.id) {
        const input = document.querySelector('[data-campaign-checkbox][value="' + item.id + '"]');
        if (input) input.checked = true;
      }
    },
    "تم إنشاء الحملة وإضافتها لقائمة المنتج."
  );

  const createPolicyQuick = async (formId, url, build, after, successText) => {
    const formEl = document.getElementById(formId);
    if (!formEl) return;
    formEl.addEventListener("submit", async event => {
      event.preventDefault();
      const form = new FormData(event.currentTarget);
      try {
        const created = await requestJson(url, { method: "POST", body: JSON.stringify(build(form)) });
        closeModal(event.currentTarget.closest(".admin-modal")?.dataset.modal);
        event.currentTarget.reset();
        await load();
        if (created.item?.id) document.getElementById(after).value = String(created.item.id);
        notify(successText);
      } catch (error) { notify(error.message, "error"); }
    });
  };

  createPolicyQuick("quickShippingPolicyForm", "/api/v1/catalog/policies/shipping",
    form => ({ name: form.get("name"), delivery_window: form.get("delivery_window"), promo_text: form.get("promo_text"),
      min_order_amount: form.get("min_order_amount") || 0, free_shipping_enabled: form.get("free_shipping_enabled") === "on" }),
    "shippingPolicyId", "تم إنشاء سياسة الشحن واختيارها للمنتج.");

  createPolicyQuick("quickReturnPolicyForm", "/api/v1/catalog/policies/return",
    form => ({ name: form.get("name"), return_window_days: Number(form.get("return_window_days") || 0), conditions: form.get("conditions"),
      fee_rule: form.get("fee_rule"), refund_method: form.get("refund_method") }),
    "returnPolicyId", "تم إنشاء سياسة الإرجاع واختيارها للمنتج.");

  createPolicyQuick("quickWarrantyPolicyForm", "/api/v1/catalog/policies/warranty",
    form => ({ name: form.get("name"), duration_days: Number(form.get("duration_days") || 0), coverage: form.get("coverage"),
      exclusions: form.get("exclusions"), claim_method: form.get("claim_method") }),
    "warrantyPolicyId", "تم إنشاء سياسة الضمان واختيارها للمنتج.");

  document.getElementById("colorSearch").addEventListener("input", renderDimensionChoices);
  document.getElementById("sizeSearch").addEventListener("input", renderDimensionChoices);
  document.getElementById("categorySearch").addEventListener("input", () => {
    document.getElementById("categorySelection").innerHTML = renderCategoryTree(configRefs?.categories || [], draftCategoryIds);
  });

  document.querySelectorAll("[data-dimension-action]").forEach(button => {
    button.addEventListener("click", () => {
      dimensionAction(button.dataset.dimensionAction);
    });
  });

  const persistDimensions = async () => requestJson(
    "/api/v1/catalog/products/" + productId + "/reference-dimensions",
    {
      method: "POST",
      body: JSON.stringify({
        color_ids: [...draftColorIds],
        size_ids: [...draftSizeIds],
      }),
    }
  );

  document.getElementById("saveDimensions").addEventListener("click", async () => {
    try {
      await persistDimensions();
      await load();
      notify("تم حفظ ألوان ومقاسات المنتج. يمكنك الآن إنشاء الـVariants منها.");
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
    const categoryIds = [...draftCategoryIds].map(Number);
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
    const stripIds = [...document.querySelectorAll("[data-strip-checkbox]:checked")].map(input => Number(input.value));
    const campaignIds = [...document.querySelectorAll("[data-campaign-checkbox]:checked")].map(input => Number(input.value));
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/badges", {
        method: "POST",
        body: JSON.stringify({ badge_ids: badgeIds }),
      });
      await requestJson("/api/v1/catalog/products/" + productId + "/hashtags", {
        method: "POST",
        body: JSON.stringify({ hashtag_ids: hashtagIds }),
      });
      await requestJson("/api/v1/catalog/products/" + productId + "/promotional-strips", {
        method: "POST",
        body: JSON.stringify({ strip_ids: stripIds }),
      });
      await requestJson("/api/v1/catalog/products/" + productId + "/campaigns", {
        method: "POST",
        body: JSON.stringify({ campaign_ids: campaignIds }),
      });
      await load();
      notify("تم حفظ الشارات والهاشتاجات وشرائط العروض والحملات.");
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

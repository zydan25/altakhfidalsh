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
  let sideCategoryReferences = [];
  let draftColorIds = new Set();
  let draftSizeIds = new Set();
  let draftCategoryIds = new Set();
  let draftSideCircleIds = new Set();
  let draftSizeGuideIds = [];
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

  const syncColorTextInputs = () => {
    document.querySelectorAll('.color-input-row').forEach(row => {
      const picker = row.querySelector('input[type="color"]');
      const text = row.querySelector('.color-text-input');
      if (!picker || !text) return;
      picker.addEventListener("input", () => { text.value = picker.value; });
      text.addEventListener("input", () => {
        const value = text.value.trim();
        if (/^#[0-9a-fA-F]{6}$/.test(value)) picker.value = value;
      });
    });
  };

  // Media rendering is isolated from the rest of hydrate(). If another
  // optional editor section throws, the image cards and their delete controls
  // must still be rendered.
  const renderMediaDeleteControls = () => {
    const rows = snapshot?.media || [];
    const mediaCard = (item) => (
      '<div class="media-thumb">' +
      '<button type="button" class="media-delete-overlay" aria-label="حذف الصورة" title="حذف الصورة" data-delete-media="' + item.id + '">×</button>' +
      (item.url
        ? '<img src="' + escapeHtml(item.url) + '" alt="' +
          escapeHtml(item.color_name || "صورة المنتج") + '">'
        : '<span>صورة</span>') +
      '<div class="media-thumb-meta"><small>' +
        (item.color_name ? escapeHtml(item.color_name) : 'عام') +
        '</small><small>#' + item.id + '</small></div>' +
      '<button type="button" class="danger-button media-delete-button" ' +
        'data-delete-media="' + item.id + '">حذف الصورة</button>' +
      '</div>'
    );

    const preview = document.getElementById("mediaPreview");
    if (preview) preview.innerHTML = rows.map(mediaCard).join("");

    const groups = document.getElementById("mediaColorGroups");
    if (!groups) return;
    const colors = (configRefs?.colors || optionRefs?.colors || [])
      .filter(color =>
        color.is_active &&
        (draftColorIds.has(Number(color.id)) ||
          rows.some(x => Number(x.color_id) === Number(color.id)))
      );
    groups.innerHTML = colors.length
      ? colors.map(color => {
          const colorRows = rows.filter(
            x => String(x.color_id || "") === String(color.id)
          );
          const bg = color.hex_code || "#111827";
          return '<article class="color-media-card">' +
            '<div class="color-media-head"><div class="manage-card-title">' +
              '<span class="color-swatch" style="background:' + escapeHtml(bg) + '"></span>' +
              '<div><strong>' + escapeHtml(color.name) + '</strong><small>' +
                colorRows.length + ' صورة</small></div></div></div>' +
            '<div class="media-card-grid">' +
              (colorRows.length
                ? colorRows.map(mediaCard).join("")
                : '<div class="media-empty">لم تُرفع صور لهذا اللون بعد.</div>') +
            '</div></article>';
        }).join("")
      : '<div class="empty-state compact"><strong>لا توجد صور ألوان.</strong>' +
        '<span class="muted">أضف لونًا أو ارفع صورة خاصة بلون أولًا.</span></div>';
    const count = document.getElementById("mediaTotalCount");
    if (count) count.textContent = rows.length + " صورة";
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
    try {
      hydrate();
    } catch (error) {
      notify(error?.message || "تعذر رسم بعض أجزاء معالج المنتج.", "error");
    } finally {
      try {
        renderMediaDeleteControls();
      } catch (error) {
        // Keep media controls best-effort; never block the rest of the editor.
      }
    }
    // These sections are independent of the rest of hydrate(); always render
    // them after the snapshot is available so one optional UI error cannot
    // leave the appearance/shipping/recommendation panels empty.
    renderProductCardEditor();
    renderDeliveryBadges();
    renderRecommendationEditor();
    await refreshSideCategoryReferences();

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

  const selectedCategoryIds = () =>
    [...draftCategoryIds]
      .map(Number)
      .filter(id => Number.isFinite(id) && id > 0);

  const refreshSideCategoryReferences = async () => {
    const categoryIds = selectedCategoryIds();
    sideCategoryReferences = [];

    if (!categoryIds.length) {
      renderSideCategoryCircles();
      return;
    }

    const params = new URLSearchParams();
    categoryIds.forEach(categoryId => params.append("category_id", String(categoryId)));

    try {
      const response = await requestJson(
        "/api/v1/catalog/reference/product-side-categories?" + params.toString()
      );

      const seen = new Set();
      sideCategoryReferences = (response.items || [])
        .flatMap(sideCategory => (sideCategory.circles || []).map(circle => ({
          ...circle,
          side_category_name: sideCategory.name,
          root_category_id: sideCategory.root_category_id,
          root_category_name: sideCategory.root_category_name || "—",
        })))
        .filter(circle => {
          const key = Number(circle.id);
          if (!Number.isFinite(key) || seen.has(key)) return false;
          seen.add(key);
          return true;
        });

      configRefs = configRefs || {};
      configRefs.available_side_category_circles = sideCategoryReferences;
      renderSideCategoryCircles();
    } catch (error) {
      renderSideCategoryCircles(
        error?.message || "تعذر تحميل الفئات الجانبية من الخادم."
      );
    }
  };

  const renderSideCategoryCircles = (errorText = "") => {
    const root = document.getElementById("sideCategoryCircleSelection");
    const count = document.getElementById("sideCategoryCircleCount");
    if (!root) return;

    const query = (document.getElementById("sideCategoryCircleSearch")?.value || "").trim().toLocaleLowerCase();
    const hasCategorySelection = draftCategoryIds.size > 0;

    const circles = sideCategoryReferences.filter(circle => {
      if (!circle) return false;
      const searchMatches =
        !query ||
        String(circle.name || "").toLocaleLowerCase().includes(query) ||
        String(circle.side_category_name || "").toLocaleLowerCase().includes(query) ||
        String(circle.root_category_name || "").toLocaleLowerCase().includes(query);
      return searchMatches;
    });

    if (hasCategorySelection) {
      const compatibleIds = new Set(circles.map(circle => Number(circle.id)));
      [...draftSideCircleIds].forEach(id => {
        if (!compatibleIds.has(Number(id))) draftSideCircleIds.delete(Number(id));
      });
    }

    if (count) count.textContent = draftSideCircleIds.size + " دائرة";

    if (errorText) {
      root.innerHTML = '<div class="empty-state compact"><strong>' + escapeHtml(errorText) + '</strong><span class="muted">تحقق من الاتصال ثم أعد تحميل الخطوة.</span></div>';
      return;
    }

    if (!circles.length) {
      root.innerHTML = hasCategorySelection
        ? '<div class="empty-state compact"><strong>لا توجد دوائر فئات جانبية لهذا الجذر.</strong><span class="muted">أضف الفئات الجانبية ودوائرها تحت القسم الرئيسي المختار من إدارة الفئات الجانبية.</span></div>'
        : '<div class="empty-state compact"><strong>اختر فئة من التصنيفات أولًا.</strong><span class="muted">سيتم تحديد الجذر تلقائيًا ثم جلب الفئات الجانبية ودوائرها التابعة له.</span></div>';
      return;
    }

    const groups = new Map();
    circles.forEach(circle => {
      const key = String(circle.side_category_id);
      if (!groups.has(key)) {
        groups.set(key, {
          name: circle.side_category_name || "فئة جانبية",
          rootCategoryName: circle.root_category_name || "—",
          circles: [],
        });
      }
      groups.get(key).circles.push(circle);
    });

    root.innerHTML = [...groups.values()].map(group =>
      '<section class="side-circle-picker-group">' +
        '<div class="side-circle-picker-heading"><div><span class="eyebrow">القسم الرئيسي · ' +
        escapeHtml(group.rootCategoryName) +
        '</span><strong>' + escapeHtml(group.name) +
        '</strong></div><span class="status-pill">' + group.circles.length + ' دائرة</span></div>' +
        '<div class="side-circle-picker-grid">' +
        group.circles.map(circle => {
          const checked = draftSideCircleIds.has(Number(circle.id));
          return '<label class="side-circle-picker-card ' + (checked ? "is-selected" : "") + '">' +
            '<input type="checkbox" value="' + circle.id + '" data-side-circle-checkbox ' + (checked ? 'checked' : '') + '>' +
            '<span class="side-circle-picker-media">' +
            (circle.image_url ? '<img src="' + escapeHtml(circle.image_url) + '" alt="' + escapeHtml(circle.name) + '">' : '<span>○</span>') +
            '</span>' +
            '<span class="side-circle-picker-copy"><strong>' + escapeHtml(circle.name) + '</strong><small>' +
            escapeHtml(group.name) + ' · ' + (circle.product_count || 0) + ' منتج</small></span>' +
            '<span class="side-circle-picker-check">' + (checked ? "✓" : "○") + '</span>' +
            '</label>';
        }).join("") +
        '</div></section>'
    ).join("");
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

  const renderSizeGuideChoices = () => {
    const root = document.getElementById("sizeGuideSelection");
    if (!root) return;
    const query = (document.getElementById("sizeGuideSearch")?.value || "").trim().toLocaleLowerCase();
    const guides = (configRefs?.size_guides || []).slice();

    guides.sort((a, b) => {
      const ai = draftSizeGuideIds.indexOf(Number(a.id));
      const bi = draftSizeGuideIds.indexOf(Number(b.id));
      if (ai >= 0 && bi >= 0) return ai - bi;
      if (ai >= 0) return -1;
      if (bi >= 0) return 1;
      return String(a.name || "").localeCompare(String(b.name || ""), "ar");
    });

    const filtered = guides.filter(guide =>
      !query ||
      String(guide.name || "").toLocaleLowerCase().includes(query) ||
      String(guide.guide_type || "").toLocaleLowerCase().includes(query) ||
      String(guide.fit_type || "").toLocaleLowerCase().includes(query)
    );

    root.innerHTML = filtered.length
      ? filtered.map(guide => {
          const id = Number(guide.id);
          const selected = draftSizeGuideIds.includes(id);
          const order = selected ? draftSizeGuideIds.indexOf(id) + 1 : 0;
          return '<article class="reference-choice-card ' + (selected ? "is-selected" : "") + '">' +
            '<label style="display:flex;align-items:center;gap:8px;flex:1;min-width:0">' +
              '<input type="checkbox" value="' + id + '" data-size-guide-checkbox ' + (selected ? "checked" : "") + '>' +
              '<span class="size-choice-badge">' + (selected ? order : "—") + '</span>' +
              '<span class="reference-choice-copy"><strong>' + escapeHtml(guide.name || "جدول مقاسات") +
              '</strong><small>' + escapeHtml(guide.fit_type || guide.guide_type || "جدول عام") + '</small></span>' +
            '</label>' +
            '<span style="display:flex;gap:4px;flex:0 0 auto">' +
              '<button type="button" class="ghost-button quick-add-button" data-size-guide-move="up" data-size-guide-id="' + id + '"' +
                (!selected || order <= 1 ? " disabled" : "") + '>↑</button>' +
              '<button type="button" class="ghost-button quick-add-button" data-size-guide-move="down" data-size-guide-id="' + id + '"' +
                (!selected || order >= draftSizeGuideIds.length ? " disabled" : "") + '>↓</button>' +
            '</span>' +
          '</article>';
        }).join("")
      : '<div class="empty-state compact"><strong>لا توجد جداول مقاسات مطابقة.</strong><span class="muted">أنشئ جدولًا من إدارة جداول المقاسات ثم سيظهر هنا.</span></div>';

    const count = document.getElementById("sizeGuideCount");
    const summary = document.getElementById("sizeGuideSelectionSummary");
    if (count) count.textContent = draftSizeGuideIds.length + " محدد";
    if (summary) summary.textContent = draftSizeGuideIds.length + " محدد";
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

  const cardLabels = {
    card_background_color:"لون خلفية البطاقة",card_background_opacity:"شفافية خلفية البطاقة",card_radius:"نصف قطر البطاقة",
    show_name:"إظهار اسم المنتج",name_font_size:"حجم اسم المنتج",name_font_weight:"وزن اسم المنتج",name_color:"لون اسم المنتج",
    name_background_color:"خلفية اسم المنتج",name_background_opacity:"شفافية خلفية الاسم",name_max_lines:"أقصى أسطر للاسم",
    show_short_description:"إظهار الوصف القصير",short_description_font_size:"حجم الوصف القصير",short_description_font_weight:"وزن الوصف القصير",
    short_description_color:"لون الوصف القصير",short_description_background_color:"خلفية الوصف القصير",short_description_background_opacity:"شفافية خلفية الوصف",short_description_max_lines:"أسطر الوصف",
    show_price:"إظهار السعر",price_font_size:"حجم السعر",price_font_weight:"وزن السعر",price_color:"لون السعر",price_background_color:"خلفية السعر",price_background_opacity:"شفافية خلفية السعر",
    show_compare_price:"إظهار السعر قبل الخصم",compare_price_font_size:"حجم السعر قبل الخصم",compare_price_font_weight:"وزن السعر قبل الخصم",
    compare_price_color:"لون السعر قبل الخصم",compare_price_background_color:"خلفية السعر قبل الخصم",compare_price_background_opacity:"شفافية خلفية السعر قبل الخصم",
    compare_price_text_decoration:"خط السعر قبل الخصم",
    show_currency:"إظهار رمز العملة",currency_font_size:"حجم رمز العملة",currency_font_weight:"وزن رمز العملة",currency_color:"لون رمز العملة",
    currency_background_color:"خلفية رمز العملة",currency_background_opacity:"شفافية خلفية العملة",
    show_size:"إظهار المقاس",size_font_size:"حجم المقاس",size_font_weight:"وزن المقاس",size_color:"لون المقاس",size_background_color:"خلفية المقاس",size_background_opacity:"شفافية خلفية المقاس",
    show_brand:"إظهار العلامة التجارية",brand_position:"موقع العلامة التجارية",brand_background_color:"خلفية العلامة",brand_text_color:"لون العلامة",brand_font_size:"حجم خط العلامة",brand_radius:"نصف قطر العلامة",
    show_product_badges:"إظهار شارات المنتج",product_badge_position:"الموقع الافتراضي للشارات",product_badge_font_size:"حجم خط الشارات",product_badge_radius:"نصف قطر الشارات",product_badge_max:"الحد الأقصى للشارات",
    show_trend_badge:"إظهار شارة الترند",trend_badge_text:"نص شارة الترند",trend_badge_background_color:"خلفية شارة الترند",trend_badge_text_color:"لون نص شارة الترند",trend_badge_font_size:"حجم شارة الترند",trend_badge_radius:"نصف قطر شارة الترند",
    discount_badge_background_color:"خلفية شارة الخصم",discount_badge_text_color:"لون نص شارة الخصم",discount_badge_font_size:"حجم خط شارة الخصم",discount_badge_font_weight:"وزن شارة الخصم",discount_badge_radius:"نصف قطر شارة الخصم",
    show_trend_hashtag:"إظهار هاشتاج الترند",trend_hashtag_text_color:"لون هاشتاج الترند",trend_hashtag_background_color:"خلفية هاشتاج الترند",trend_hashtag_use_background:"خلفية هاشتاج الترند",
    trend_hashtag_font_size:"حجم هاشتاج الترند",trend_hashtag_font_weight:"وزن هاشتاج الترند",trend_show_arrow:"إظهار سهم الترند",trend_arrow_text:"رمز سهم الترند",trend_arrow_color:"لون سهم الترند",trend_ribbon_gap:"المسافة في شريط الترند",
    colors_show:"إظهار الألوان",colors_position:"موقع الألوان",colors_direction:"اتجاه الألوان",colors_size:"حجم دائرة اللون",colors_gap:"المسافة بين الألوان",colors_max:"عدد الألوان",colors_container_size:"حجم حاوية اللون",colors_border_width:"سُمك حدود اللون",
    meta_show:"إظهار المعلومة العلوية",meta_position:"موقع المعلومة العلوية",meta_font_size:"حجم المعلومة العلوية",meta_background_color:"خلفية المعلومة العلوية",meta_text_color:"لون المعلومة العلوية",meta_radius:"نصف قطر المعلومة",meta_padding_horizontal:"الحشو الأفقي للمعلومة",meta_padding_vertical:"الحشو الرأسي للمعلومة"
  };
  const cardGroups = [
    ["البطاقة والاسم", ["card_","show_name","name_","show_short_description","short_description_"]],
    ["السعر والعملات", ["show_price","price_","show_compare_price","compare_price_","show_currency","currency_"]],
    ["المقاس والعلامة", ["show_size","size_","show_brand","brand_"]],
    ["الشارات والترند", ["show_product_badges","product_badge_","discount_badge_","show_trend_badge","trend_badge_","show_trend_hashtag","trend_hashtag_","trend_"]],
    ["الألوان والمعلومات", ["colors_","meta_"]]
  ];
  const cardGroupFor = key => {
    for (const [title, prefixes] of cardGroups) {
      if (prefixes.some(prefix => prefix === key || key.startsWith(prefix))) return title;
    }
    return "عام";
  };
  const selectOptionsFor = (key) => {
    if (key.endsWith("text_decoration")) return [["line_through","خط فوق النص"],["none","بدون"]];
    if (key === "brand_position" || key === "colors_position" || key === "meta_position") {
      return [["top_right","أعلى اليمين"],["top_left","أعلى اليسار"],["bottom_right","أسفل اليمين"],["bottom_left","أسفل اليسار"]];
    }
    if (key === "product_badge_position") {
      return [
        ["above_image","أعلى الصورة"],
        ["before_name","قبل اسم المنتج"],
        ["after_name","بعد اسم المنتج"],
        ["right_of_image","يمين الصورة"],
        ["below_price","أسفل السعر"],
        ["top_right","أعلى يمين الصورة"],
        ["top_left","أعلى يسار الصورة"],
        ["bottom_right","أسفل يمين الصورة"],
        ["bottom_left","أسفل يسار الصورة"],
      ];
    }
    if (key === "colors_direction") return [["horizontal","أفقي"],["vertical","رأسي"]];
    return null;
  };
  const isColorKey = key => key.endsWith("_color");
  const renderSettingValue = (key, globalValue, currentValue) => {
    const value = currentValue ?? globalValue;
    const label = cardLabels[key] || key.replaceAll("_"," ");
    if (typeof globalValue === "boolean") {
      return '<label class="card-setting-control"><input class="setting-value" type="checkbox" data-setting-value="' + key + '" ' + (value ? "checked" : "") + '><span>مفعل</span></label>';
    }
    const options = selectOptionsFor(key);
    if (options) {
      return '<label class="card-setting-control"><select class="setting-value" data-setting-value="' + key + '">' +
        options.map(([v,t]) => '<option value="' + v + '"' + (String(value) === v ? " selected" : "") + '>' + t + '</option>').join("") +
        '</select></label>';
    }
    if (isColorKey(key) && typeof value === "string") {
      const safe = /^#[0-9a-fA-F]{6}$/.test(value) ? value : "#ffffff";
      return '<div class="card-color-row"><input class="setting-value" type="color" value="' + safe + '" data-setting-color="' + key + '"><input class="setting-value" dir="ltr" value="' + safe + '" data-setting-color-text="' + key + '" data-setting-value="' + key + '"></div>';
    }
    if (typeof globalValue === "number") {
      const step = Number(globalValue) % 1 === 0 ? "1" : "0.1";
      return '<label class="card-setting-control"><input class="setting-value" type="number" step="' + step + '" value="' + escapeHtml(value) + '" data-setting-value="' + key + '"></label>';
    }
    return '<label class="card-setting-control"><input class="setting-value" type="text" value="' + escapeHtml(value) + '" data-setting-value="' + key + '"></label>';
  };
  const renderProductCardEditor = () => {
    const root = document.getElementById("productCardEditor");
    if (!root) return;
    const global = snapshot?.product_card_global_settings || snapshot?.product_card_settings || {};
    const overrides = snapshot?.product_card_overrides || {};
    const keys = Object.keys(global);
    root.innerHTML = cardGroups.map(([title]) => {
      const groupKeys = keys.filter(key => cardGroupFor(key) === title);
      if (!groupKeys.length) return "";
      return '<details class="card-setting-group"><summary><span>' + title + '</span><small>' + groupKeys.length + ' إعداد</small></summary><div class="card-setting-body">' +
        groupKeys.map(key => {
          const inherited = !Object.prototype.hasOwnProperty.call(overrides, key);
          return '<div class="card-setting-row ' + (inherited ? "is-inherited" : "") + '" data-setting-row="' + key + '">' +
            '<label>' + (cardLabels[key] || key) + '</label>' +
            '<div class="card-setting-control ' + (inherited ? "is-inherited" : "") + '">' +
              renderSettingValue(key, global[key], inherited ? global[key] : overrides[key]) +
              '<label class="inherit-toggle"><input type="checkbox" data-setting-customize="' + key + '"' + (inherited ? "" : " checked") + '><span>تخصيص</span></label>' +
            '</div></div>';
        }).join("") + '</div></details>';
    }).join("");
  };

  const renderDeliveryBadges = () => {
    const root = document.getElementById("deliveryBadgeEditor");
    if (!root) return;
    const rows = snapshot?.delivery_badges || [];
    root.innerHTML = rows.map((row, index) => {
      const bg = /^#[0-9a-fA-F]{6}$/.test(row.background_color || "") ? row.background_color : "#f5f5f5";
      const fg = /^#[0-9a-fA-F]{6}$/.test(row.text_color || "") ? row.text_color : "#111111";
      return '<article class="delivery-badge-card" data-delivery-index="' + index + '">' +
        '<div class="delivery-badge-card-head"><div><strong>شارة التوصيل ' + (index + 1) + '</strong><small class="muted">ترتيب ' + (index + 1) + '</small></div>' +
        '<div class="delivery-badge-actions"><button type="button" class="ghost-button compact" data-delivery-up="' + index + '">↑</button><button type="button" class="ghost-button compact" data-delivery-down="' + index + '">↓</button><button type="button" class="ghost-button compact" data-delivery-delete="' + index + '">حذف</button></div></div>' +
        '<div class="delivery-badge-card-body">' +
        '<label class="full">النص<input data-delivery-field="text" value="' + escapeHtml(row.text || "") + '" maxlength="120"></label>' +
        '<label>القسم<input data-delivery-field="section" value="' + escapeHtml(row.section || "shipping") + '"></label>' +
        '<label>الأيقونة<input data-delivery-field="icon" value="' + escapeHtml(row.icon || "local_shipping") + '"></label>' +
        '<label>حجم الخط<input type="number" min="7" max="24" step="0.5" data-delivery-field="font_size" value="' + (row.font_size ?? 9) + '"></label>' +
        '<label class="check-row"><input type="checkbox" data-delivery-field="visible" ' + (row.visible !== false ? "checked" : "") + '><span><strong>إظهار</strong></span></label>' +
        '<label>لون الخلفية<span class="color-input-row"><input type="color" data-delivery-color="background_color" value="' + bg + '"><input class="color-text-input" dir="ltr" data-delivery-field="background_color" value="' + bg + '"></span></label>' +
        '<label>لون النص<span class="color-input-row"><input type="color" data-delivery-color="text_color" value="' + fg + '"><input class="color-text-input" dir="ltr" data-delivery-field="text_color" value="' + fg + '"></span></label>' +
        '</div></article>';
    }).join("") || '<div class="empty-state compact"><strong>لا توجد شارات توصيل.</strong><span class="muted">أضف أول شارة لتظهر أعلى معلومات التوصيل في تفاصيل المنتج.</span></div>';
  };

  const renderRecommendationEditor = () => {
    const root = document.getElementById("recommendationEditor");
    if (!root) return;
    const current = snapshot?.recommendation_settings || {};
    const source = current.source || "same_category";
    const choices = [
      ["same_category","من نفس الفئة","المنتجات المرتبطة بالفئة الحالية للمنتج."],
      ["parent_category","من الفئة الأب","المنتجات من مستوى الفئة الأب."],
      ["root_category","من الفئة الرئيسية العليا","المنتجات من الجذر الرئيسي للفئة."],
      ["random_all","عشوائي من كل المنتجات","منتجات عشوائية من كامل الكتالوج."]
    ];
    root.innerHTML = choices.map(([value,title,hint]) =>
      '<label class="recommendation-choice ' + (source === value ? "is-selected" : "") + '">' +
      '<input type="radio" name="recommendation-source" value="' + value + '"' + (source === value ? " checked" : "") + '>' +
      '<span><strong>' + title + '</strong><small>' + hint + '</small></span></label>'
    ).join("") +
    '<div class="recommendation-limit"><label>عدد المنتجات<input id="recommendationLimit" type="number" min="2" max="20" value="' + (current.limit || 10) + '"></label>' +
    '<label class="check-row"><input type="checkbox" checked disabled><span><strong>ترتيب عشوائي</strong><small>ثابت على أنه عشوائي من الخادم.</small></span></label></div>';
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
      '<button type="button" class="danger-button media-delete-button" data-delete-media="' + item.id + '">حذف الصورة</button></div>'
    );
    document.getElementById("mediaPreview").innerHTML = mediaRows.map(mediaCard).join("");
    document.getElementById("mediaTotalCount").textContent = mediaRows.length + " صورة";

    configRefs = configRefs || optionRefs || {};
    if (!draftsInitialized) {
      draftCategoryIds = new Set((snapshot.categories || []).map(x => String(x.id)));
      draftSideCircleIds = new Set((snapshot.side_category_circles || []).map(x => Number(x.id)));
      if (!draftSideCircleIds.size) {
        draftSideCircleIds = new Set((configRefs?.selected_side_category_circle_ids || []).map(Number));
      }
      draftColorIds = new Set((snapshot.reference_colors || []).map(x => Number(x.id)));
      draftSizeIds = new Set((snapshot.reference_sizes || []).map(x => Number(x.id)));
      if (!draftColorIds.size) {
        draftColorIds = new Set((configRefs.colors || []).filter(x => x.selected).map(x => Number(x.id)));
      }
      if (!draftSizeIds.size) {
        draftSizeIds = new Set((configRefs.sizes || []).filter(x => x.selected).map(x => Number(x.id)));
      }
      const configuredGuides = (configRefs?.size_guides || [])
        .filter(x => x.selected)
        .sort((a, b) =>
          (Number(a.sort_order ?? 999999) - Number(b.sort_order ?? 999999)) ||
          String(a.name || "").localeCompare(String(b.name || ""), "ar")
        );
      draftSizeGuideIds = configuredGuides.map(x => Number(x.id));
      draftsInitialized = true;
    }
    renderDimensionChoices();
    renderSizeGuideChoices();

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
      "side-categories": snapshot.steps["side-categories"],
      media: snapshot.steps.media,
      options: snapshot.steps.options,
      variants: snapshot.steps.variants,
      inventory: snapshot.steps.inventory,
      publish: snapshot.steps.publish,
    };
    document.querySelector("[data-panel='publish'] .checklist").innerHTML = [
      ["الأساس", steps.basics],
      ["التصنيفات", steps.categories],
      ["الفئات الجانبية", steps["side-categories"]],
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
    const selectedBadgeRows = new Map((snapshot.badges || []).map(x => [String(x.id), x]));
    const selectedHashtags = new Set((snapshot.hashtags || []).map(x => String(x.id)));
    const selectedStrips = new Set((snapshot.promotional_strips || []).map(x => String(x.id)));
    const selectedCampaigns = new Set((snapshot.campaigns || []).map(x => String(x.id)));
    const marketing = configRefs || marketingRefs || {};

    const remainingDays = (row) => {
      if (!row?.ends_at) return 0;
      const ms = new Date(row.ends_at).getTime() - Date.now();
      return ms > 0 ? Math.ceil(ms / 86400000) : 0;
    };

    document.getElementById("badgeSelection").innerHTML = (marketing.badges || []).map(x => {
      const selected = selectedBadgeRows.has(String(x.id));
      const current = selectedBadgeRows.get(String(x.id)) || {};
      const saved = current.settings || {};
      const value = (key, fallback) => saved[key] ?? fallback;
      const bg = value("background_color", x.bg_color || "#111827");
      const fg = value("text_color", x.text_color || "#ffffff");
      const font = value("font_size", 9);
      const weight = value("font_weight", 800);
      const opacity = value("background_opacity", 1);
      const position = value("position", "top_right");
      const decoration = value("text_decoration", "none");
      const positionLabels = {
        top_left:"أعلى اليسار",top_right:"أعلى اليمين",bottom_left:"أسفل اليسار",
        bottom_right:"أسفل اليمين",above_image:"أعلى الصورة",before_name:"قبل الاسم",
        after_name:"بعد الاسم",right_of_image:"يمين الصورة",below_price:"أسفل السعر"
      };
      return '<article class="product-badge-editor" data-badge-row="' + x.id + '">' +
        '<div class="product-badge-editor-head">' +
          '<label class="check-row compact-check"><input type="checkbox" value="' + x.id + '" data-badge-checkbox ' +
            (selected ? 'checked' : '') + (!x.is_active ? ' disabled' : '') + '><span><strong>' +
            escapeHtml(x.name) + '</strong><small>' + escapeHtml(x.code) + '</small></span></label>' +
          '<div class="delivery-badge-actions">' +
            '<button type="button" class="ghost-button compact" data-badge-up="' + x.id + '">↑</button>' +
            '<button type="button" class="ghost-button compact" data-badge-down="' + x.id + '">↓</button>' +
            '<button type="button" class="ghost-button compact" data-badge-open="' + x.id + '">تعديل الشكل</button>' +
          '</div>' +
        '</div>' +
        '<div class="product-badge-summary"><span>الموقع: ' + (positionLabels[position] || position) + '</span><span>الترتيب: ' + (current.sort_order ?? 0) + '</span></div>' +
        '<details class="badge-editor-details"><summary>فتح إعدادات هذه الشارة</summary>' +
        '<div class="badge-editor-grid">' +
          '<label>الترتيب<input type="number" min="0" max="99" value="' + (current.sort_order ?? 0) + '" data-badge-sort="' + x.id + '"></label>' +
          '<label>الموقع<select data-badge-position="' + x.id + '">' +
            Object.entries(positionLabels).map(([option,label]) => '<option value="' + option + '"' + (position === option ? ' selected' : '') + '>' + label + '</option>').join('') +
          '</select></label>' +
          '<label>النص المخصص<input value="' + escapeHtml(current.custom_text || '') + '" data-badge-text="' + x.id + '" maxlength="120"></label>' +
          '<label>الظهور بالأيام<input type="number" min="0" max="3650" value="' + remainingDays(current) + '" data-badge-days="' + x.id + '"></label>' +
          '<label>حجم الخط<input type="number" min="6" max="32" step="0.5" value="' + font + '" data-badge-font="' + x.id + '"></label>' +
          '<label>وزن الخط<input type="number" min="300" max="900" step="100" value="' + weight + '" data-badge-weight="' + x.id + '"></label>' +
          '<label>شفافية الخلفية<input type="number" min="0" max="1" step="0.05" value="' + opacity + '" data-badge-opacity="' + x.id + '"></label>' +
          '<label>خط فوق النص<select data-badge-decoration="' + x.id + '"><option value="none"' + (decoration !== "line_through" ? ' selected' : '') + '>بدون خط</option><option value="line_through"' + (decoration === "line_through" ? ' selected' : '') + '>خط فوق النص</option></select></label>' +
          '<label>الخلفية HEX<span class="color-input-row"><input type="color" value="' + bg + '" data-badge-bg="' + x.id + '"><input dir="ltr" value="' + bg + '" data-badge-bg-text="' + x.id + '" maxlength="7"></span></label>' +
          '<label>النص HEX<span class="color-input-row"><input type="color" value="' + fg + '" data-badge-fg="' + x.id + '"><input dir="ltr" value="' + fg + '" data-badge-fg-text="' + x.id + '" maxlength="7"></span></label>' +
        '</div></details>' +
      '</article>';
    }).join("") || '<div class="empty-state compact"><strong>لا توجد شارات.</strong><span class="muted">أضف شارة جديدة من الزر.</span></div>';

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

    renderProductCardEditor();
    renderDeliveryBadges();
    renderRecommendationEditor();
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
    refreshSideCategoryReferences();
  });

  document.getElementById("sideCategoryCircleSelection").addEventListener("change", (event) => {
    const input = event.target.closest("[data-side-circle-checkbox]");
    if (!input) return;
    const id = Number(input.value);
    if (input.checked) draftSideCircleIds.add(id);
    else draftSideCircleIds.delete(id);
    input.closest(".side-circle-picker-card")?.classList.toggle("is-selected", input.checked);
    const check = input.closest(".side-circle-picker-card")?.querySelector(".side-circle-picker-check");
    if (check) check.textContent = input.checked ? "✓" : "○";
    const count = document.getElementById("sideCategoryCircleCount");
    if (count) count.textContent = draftSideCircleIds.size + " دائرة";
  });

  document.getElementById("sideCategoryCircleSearch")?.addEventListener("input", renderSideCategoryCircles);

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

  document.getElementById("sizeGuideSelection")?.addEventListener("change", (event) => {
    const input = event.target.closest("[data-size-guide-checkbox]");
    if (!input) return;
    const id = Number(input.value);
    if (!Number.isFinite(id) || id <= 0) return;

    if (input.checked) {
      if (!draftSizeGuideIds.includes(id)) draftSizeGuideIds.push(id);
    } else {
      draftSizeGuideIds = draftSizeGuideIds.filter(item => Number(item) !== id);
    }
    renderSizeGuideChoices();
  });

  document.getElementById("sizeGuideSelection")?.addEventListener("click", (event) => {
    const button = event.target.closest("[data-size-guide-move]");
    if (!button) return;

    const id = Number(button.dataset.sizeGuideId);
    const direction = button.dataset.sizeGuideMove;
    const index = draftSizeGuideIds.indexOf(id);
    if (index < 0) return;

    const nextIndex = direction === "up" ? index - 1 : index + 1;
    if (nextIndex < 0 || nextIndex >= draftSizeGuideIds.length) return;

    const reordered = [...draftSizeGuideIds];
    [reordered[index], reordered[nextIndex]] = [reordered[nextIndex], reordered[index]];
    draftSizeGuideIds = reordered;
    renderSizeGuideChoices();
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
          hex_code: (form.get("hex_code_text") || form.get("hex_code") || "").trim(),
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
    const visualDefaults = {
      font_size: Number(form.get("font_size") || 9),
      font_weight: Number(form.get("font_weight") || 800),
      background_opacity: Number(form.get("background_opacity") || 1),
      text_decoration: form.get("text_decoration") || "none",
    };
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
      const id = created.item?.id;
      const checkbox = document.querySelector('[data-badge-checkbox][value="' + id + '"]');
      if (checkbox) checkbox.checked = true;
      if (id) {
        const set = (selector, value) => {
          const el = document.querySelector(selector + id + '"]');
          if (el) el.value = value;
        };
        set('[data-badge-font="', visualDefaults.font_size);
        set('[data-badge-weight="', visualDefaults.font_weight);
        set('[data-badge-opacity="', visualDefaults.background_opacity);
        set('[data-badge-decoration="', visualDefaults.text_decoration);
        const bg = form.get("bg_color");
        const fg = form.get("text_color");
        set('[data-badge-bg-text="', bg);
        set('[data-badge-fg-text="', fg);
        await document.getElementById("saveMarketing")?.click();
      }
      notify("تم إنشاء الشارة وربط تنسيقها بالمنتج.");
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
  document.getElementById("sizeGuideSearch")?.addEventListener("input", renderSizeGuideChoices);
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

  document.getElementById("saveSizeGuides")?.addEventListener("click", async () => {
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/size-guides", {
        method: "POST",
        body: JSON.stringify({ guide_ids: draftSizeGuideIds }),
      });
      await load();
      notify(
        draftSizeGuideIds.length
          ? "تم حفظ جداول المقاسات وترتيب ظهورها."
          : "تم إلغاء ربط جداول المقاسات بهذا المنتج."
      );
    } catch (error) {
      notify(error.message, "error");
    }
  });

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

  document.getElementById("saveSideCategoryCircles").addEventListener("click", async () => {
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/side-category-circles", {
        method: "POST",
        body: JSON.stringify({ circle_ids: [...draftSideCircleIds] }),
      });
      await load();
      notify("تم حفظ الفئات الجانبية للمنتج.");
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
    const hashtagIds = [...document.querySelectorAll("[data-hashtag-checkbox]:checked")].map(input => Number(input.value));
    const stripIds = [...document.querySelectorAll("[data-strip-checkbox]:checked")].map(input => Number(input.value));
    const campaignIds = [...document.querySelectorAll("[data-campaign-checkbox]:checked")].map(input => Number(input.value));
    try {
      // Product badges are intentionally managed only from the standalone
      // presentation screen, so this form never overwrites their settings.
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
      notify("تم حفظ الهاشتاجات وشرائط العروض والحملات.");
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

  const readCardOverrides = () => {
    const overrides = {};
    document.querySelectorAll("[data-setting-row]").forEach(row => {
      const key = row.dataset.settingRow;
      const custom = row.querySelector("[data-setting-customize]")?.checked;
      const input = row.querySelector("[data-setting-value]");
      const checkbox = row.querySelector('input[type="checkbox"][data-setting-value]');
      if (!custom) return;
      if (checkbox) {
        overrides[key] = checkbox.checked;
      } else if (isNaN(Number(input?.value)) || isColorKey(key) || typeof input?.value === "string") {
        if (isColorKey(key)) {
          const text = row.querySelector("[data-setting-color-text]")?.value?.trim() || "";
          if (/^#[0-9a-fA-F]{6}$/.test(text)) overrides[key] = text.toLowerCase();
        } else {
          const globalValue = snapshot?.product_card_global_settings?.[key];
          if (typeof globalValue === "number") overrides[key] = Number(input?.value);
          else overrides[key] = input?.value ?? "";
        }
      }
    });
    return overrides;
  };

  const readDeliveryBadges = () => [...document.querySelectorAll(".delivery-badge-card")].map(card => {
    const get = field => card.querySelector('[data-delivery-field="' + field + '"]');
    const row = {
      id: card.dataset.deliveryIndex || undefined,
      text: get("text")?.value?.trim() || "",
      section: get("section")?.value?.trim() || "shipping",
      icon: get("icon")?.value?.trim() || "local_shipping",
      font_size: Number(get("font_size")?.value || 9),
      visible: get("visible")?.checked !== false,
      background_color: get("background_color")?.value || "#f5f5f5",
      text_color: get("text_color")?.value || "#111111",
    };
    return row;
  }).filter(row => row.text);

  document.getElementById("productCardEditor")?.addEventListener("change", event => {
    const toggle = event.target.closest("[data-setting-customize]");
    if (toggle) {
      const row = toggle.closest("[data-setting-row]");
      const control = row?.querySelector(".card-setting-control");
      if (control) control.classList.toggle("is-inherited", !toggle.checked);
    }
    const color = event.target.closest("[data-setting-color]");
    if (color) {
      const peer = color.closest(".card-color-row")?.querySelector("[data-setting-color-text]");
      if (peer) peer.value = color.value;
    }
    const select = event.target.closest("[data-setting-value]");
    if (select) select.dataset.changed = "1";
  });
  document.getElementById("badgeSelection")?.addEventListener("input", event => {
    const text = event.target.closest("[data-badge-bg-text],[data-badge-fg-text]");
    if (text && /^#[0-9a-fA-F]{6}$/.test(text.value.trim())) {
      const picker = text.closest(".color-input-row")?.querySelector('input[type="color"]');
      if (picker) picker.value = text.value.trim();
    }
  });
  document.getElementById("badgeSelection")?.addEventListener("change", event => {
    const picker = event.target.closest("[data-badge-bg],[data-badge-fg]");
    if (!picker) return;
    const suffix = picker.dataset.badgeBg != null ? "bg" : "fg";
    const id = picker.dataset.badgeBg ?? picker.dataset.badgeFg;
    const text = picker.closest(".color-input-row")?.querySelector("[data-badge-" + suffix + '-text="' + id + '"]');
    if (text) text.value = picker.value;
  });

  document.getElementById("productCardEditor")?.addEventListener("input", event => {
    const colorText = event.target.closest("[data-setting-color-text]");
    if (colorText && /^#[0-9a-fA-F]{6}$/.test(colorText.value.trim())) {
      const peer = colorText.closest(".card-color-row")?.querySelector("[data-setting-color]");
      if (peer) peer.value = colorText.value.trim();
    }
  });

  document.getElementById("saveProductCard")?.addEventListener("click", async () => {
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/display-settings", {
        method:"POST",
        body:JSON.stringify({card_overrides:readCardOverrides()}),
      });
      await load();
      notify("تم حفظ تخصيص بطاقة هذا المنتج. القيم غير المخصصة ستبقى موروثة من الإعداد العام.");
    } catch(error){notify(error.message,"error");}
  });

  document.getElementById("resetProductCardOverrides")?.addEventListener("click", async () => {
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/display-settings", {
        method:"POST",
        body:JSON.stringify({card_overrides:{}}),
      });
      await load();
      notify("عاد المنتج بالكامل إلى إعدادات بطاقة المنتج العامة.");
    } catch(error){notify(error.message,"error");}
  });

  const deliverySwap = (from, to) => {
    const rows = [...document.querySelectorAll(".delivery-badge-card")];
    if (!rows[from] || !rows[to]) return;
    const payload = readDeliveryBadges();
    const item = payload.splice(from, 1)[0];
    payload.splice(to, 0, item);
    snapshot.delivery_badges = payload;
    renderDeliveryBadges();
  };
  document.getElementById("deliveryBadgeEditor")?.addEventListener("input", event => {
    const text = event.target.closest('[data-delivery-field="background_color"],[data-delivery-field="text_color"]');
    if (text && /^#[0-9a-fA-F]{6}$/.test(text.value.trim())) {
      const field = text.dataset.deliveryField;
      const picker = text.closest(".color-input-row")?.querySelector('[data-delivery-color="' + field + '"]');
      if (picker) picker.value = text.value.trim();
    }
  });
  document.getElementById("deliveryBadgeEditor")?.addEventListener("change", event => {
    const picker = event.target.closest("[data-delivery-color]");
    if (picker) {
      const field = picker.dataset.deliveryColor;
      const text = picker.closest(".color-input-row")?.querySelector('[data-delivery-field="' + field + '"]');
      if (text) text.value = picker.value;
    }
  });
  document.getElementById("deliveryBadgeEditor")?.addEventListener("click", event => {
    const up = event.target.closest("[data-delivery-up]");
    const down = event.target.closest("[data-delivery-down]");
    const del = event.target.closest("[data-delivery-delete]");
    const index = Number((up||down||del)?.dataset.deliveryUp ?? (up||down||del)?.dataset.deliveryDown ?? (up||down||del)?.dataset.deliveryDelete);
    if (up && index > 0) deliverySwap(index, index - 1);
    if (down) deliverySwap(index, index + 1);
    if (del) {
      const rows = readDeliveryBadges();
      rows.splice(index,1);
      snapshot.delivery_badges = rows;
      renderDeliveryBadges();
    }
  });
  document.getElementById("addDeliveryBadge")?.addEventListener("click", () => {
    snapshot.delivery_badges = snapshot.delivery_badges || [];
    snapshot.delivery_badges.push({text:"شحن سريع",section:"shipping",icon:"local_shipping",font_size:9,visible:true,background_color:"#f5f5f5",text_color:"#111111"});
    renderDeliveryBadges();
  });
  document.getElementById("saveDeliveryBadges")?.addEventListener("click", async () => {
    try {
      await requestJson("/api/v1/catalog/products/" + productId + "/display-settings", {
        method:"POST",
        body:JSON.stringify({delivery_badges:readDeliveryBadges()}),
      });
      await load();
      notify("تم حفظ شارات التوصيل الخاصة بالمنتج.");
    } catch(error){notify(error.message,"error");}
  });

  document.getElementById("recommendationEditor")?.addEventListener("change", event => {
    const choice = event.target.closest('input[name="recommendation-source"]');
    if (choice) {
      document.querySelectorAll(".recommendation-choice").forEach(x => x.classList.toggle("is-selected", x.contains(choice)));
    }
  });
  document.getElementById("saveRecommendations")?.addEventListener("click", async () => {
    try {
      const source = document.querySelector('input[name="recommendation-source"]:checked')?.value || "same_category";
      const limit = Number(document.getElementById("recommendationLimit")?.value || 10);
      await requestJson("/api/v1/catalog/products/" + productId + "/display-settings", {
        method:"POST",
        body:JSON.stringify({recommendation_settings:{source,limit}}),
      });
      await load();
      notify("تم حفظ مصدر التوصيات وعدد المنتجات، وسيظهر الترتيب عشوائيًا.");
    } catch(error){notify(error.message,"error");}
  });

  document.getElementById("badgeSelection")?.addEventListener("click", event => {
    const button = event.target.closest("[data-badge-open]");
    const up = event.target.closest("[data-badge-up]");
    const down = event.target.closest("[data-badge-down]");
    if (button) {
      const details = button.closest(".product-badge-editor")?.querySelector(".badge-editor-details");
      if (details) details.open = true;
      return;
    }
    if (!up && !down) return;
    const card = (up || down).closest(".product-badge-editor");
    const target = up ? card?.previousElementSibling : card?.nextElementSibling;
    if (!card || !target) return;
    if (up) card.parentNode.insertBefore(card,target); else card.parentNode.insertBefore(target,card);
    document.querySelectorAll("[data-badge-sort]").forEach((input,index)=>input.value=index);
  });

  syncColorTextInputs();
  load();
})();

(() => {
  const shell = document.querySelector(".wizard-shell");
  if (!shell) return;

  const productId = shell.dataset.productId;
  const message = document.getElementById("wizardMessage");
  const panels = [...document.querySelectorAll(".wizard-panel")];
  const steps = [...document.querySelectorAll(".wizard-step")];
  let snapshot = null;

  const notify = (text, type = "success") => {
    message.textContent = text;
    message.className = "alert " + type;
    message.hidden = false;
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const requestJson = async (url, options = {}) => {
    const response = await fetch(url, {
      headers: { "Content-Type": "application/json", ...(options.body instanceof FormData ? {} : {}) },
      ...options,
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.detail || data.error || "تعذر تنفيذ العملية");
    return data;
  };

  const load = async () => {
    try {
      const result = await requestJson("/api/v1/admin/catalog/products/" + productId + "/wizard");
      snapshot = result.item;
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

    document.getElementById("mediaPreview").innerHTML = (snapshot.media || []).map(item => (
      '<div class="media-thumb"><span>صورة</span><small>#' + item.asset_id + '</small></div>'
    )).join("");

    const steps = {
      basics: snapshot.steps.basics,
      categories: snapshot.steps.categories,
      media: snapshot.steps.media,
      options: snapshot.steps.options,
      variants: snapshot.steps.variants,
      publish: snapshot.steps.publish,
    };
    document.querySelector("[data-panel='publish'] .checklist").innerHTML = [
      ["الأساس", steps.basics],
      ["التصنيفات", steps.categories],
      ["الوسائط", steps.media],
      ["الخيارات", steps.options],
      ["المتغيرات", steps.variants],
      ["جاهز للنشر", snapshot.publishable],
    ].map(([label, ok]) => '<div class="checklist-row"><span class="' + (ok ? "ok" : "pending") + '">' + (ok ? "✓" : "•") + '</span><strong>' + label + '</strong><small>' + (ok ? "مكتمل" : "يحتاج إعدادًا") + '</small></div>').join("");
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

  document.getElementById("basicsForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const body = {
      sku: document.getElementById("productSku").value.trim(),
      name: document.getElementById("productName").value.trim(),
      description: document.getElementById("productDescription").value,
      base_price: document.getElementById("productPrice").value,
      material: document.getElementById("productMaterial").value,
      care_instructions: document.getElementById("productCare").value,
    };
    try {
      await requestJson("/api/v1/admin/catalog/products/" + productId, { method: "PATCH", body: JSON.stringify(body) });
      await load();
      notify("تم حفظ البيانات الأساسية.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("saveCategories").addEventListener("click", async () => {
    const categoryIds = [...document.querySelectorAll("[data-category-checkbox]:checked")].map(input => Number(input.value));
    try {
      await requestJson("/api/v1/admin/catalog/products/" + productId + "/categories", { method: "POST", body: JSON.stringify({ category_ids: categoryIds }) });
      await load();
      notify("تم حفظ التصنيفات.");
    } catch (error) { notify(error.message, "error"); }
  });

  document.getElementById("uploadMedia").addEventListener("click", async () => {
    const input = document.getElementById("productMedia");
    if (!input.files.length) return notify("اختر صورة واحدة على الأقل.", "error");
    const body = new FormData();
    [...input.files].forEach(file => body.append("files", file));
    try {
      const response = await fetch("/api/v1/admin/catalog/products/" + productId + "/media", { method: "POST", body });
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
      await requestJson("/api/v1/admin/catalog/products/" + productId + "/options", {
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

  document.getElementById("variantForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      await requestJson("/api/v1/admin/catalog/products/" + productId + "/variants", {
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

  document.getElementById("publishProduct").addEventListener("click", async () => {
    if (!snapshot?.publishable) return;
    try {
      await requestJson("/api/v1/admin/catalog/products/" + productId + "/publish", { method: "POST", body: "{}" });
      await load();
      notify("تم نشر المنتج.");
    } catch (error) { notify(error.message, "error"); }
  });

  load();
})();

(() => {
  const dataEl = document.getElementById("sideCategoryData");
  if (!dataEl) return;

  let items = [];
  try { items = JSON.parse(dataEl.textContent || "[]") || []; } catch { items = []; }

  const sideModal = document.querySelector('[data-modal="sideCategoryEditor"]');
  const circleModal = document.querySelector('[data-modal="sideCircleEditor"]');

  const open = modal => {
    if (!modal) return;
    modal.hidden = false;
    document.body.classList.add("modal-open");
    requestAnimationFrame(() => modal.querySelector("input,select,textarea")?.focus());
  };
  const close = modal => {
    if (!modal) return;
    modal.hidden = true;
    document.body.classList.remove("modal-open");
  };

  const sideById = id => items.find(x => Number(x.id) === Number(id));

  const sideForm = {
    action: document.getElementById("sideCategoryAction"),
    id: document.getElementById("sideCategoryId"),
    title: document.getElementById("sideCategoryEditorTitle"),
    root: document.getElementById("sideCategoryRoot"),
    name: document.getElementById("sideCategoryName"),
    slug: document.getElementById("sideCategorySlug"),
    badge: document.getElementById("sideCategoryBadge"),
    sort: document.getElementById("sideCategorySort"),
  };

  const circleForm = {
    action: document.getElementById("sideCircleAction"),
    id: document.getElementById("sideCircleId"),
    title: document.getElementById("sideCircleEditorTitle"),
    side: document.getElementById("sideCircleSide"),
    name: document.getElementById("sideCircleName"),
    slug: document.getElementById("sideCircleSlug"),
    file: document.getElementById("sideCircleFiles"),
    badge: document.getElementById("sideCircleBadge"),
    sort: document.getElementById("sideCircleSort"),
    currentPreview: document.getElementById("sideCircleCurrentPreview"),
    currentImage: document.getElementById("sideCircleCurrentImage"),
    fileLabel: document.getElementById("sideCircleFileLabel"),
  };

  document.querySelectorAll("[data-side-create]").forEach(button => {
    button.addEventListener("click", () => {
      sideForm.action.value = "create_side_category";
      sideForm.id.value = "";
      sideForm.title.textContent = "إضافة فئة جانبية جديدة";
      sideForm.root.value = "";
      sideForm.name.value = "";
      sideForm.slug.value = "";
      sideForm.badge.value = "";
      sideForm.sort.value = "0";
      open(sideModal);
    });
  });

  document.querySelectorAll("[data-side-edit]").forEach(button => {
    button.addEventListener("click", () => {
      const row = sideById(button.dataset.sideEdit);
      if (!row) return;
      sideForm.action.value = "update_side_category";
      sideForm.id.value = String(row.id);
      sideForm.title.textContent = "تعديل الفئة الجانبية";
      sideForm.root.value = String(row.root_category_id || "");
      sideForm.name.value = row.name || "";
      sideForm.slug.value = row.slug || "";
      sideForm.badge.value = String(row.badge_id || "");
      sideForm.sort.value = String(row.sort_order || 0);
      open(sideModal);
    });
  });

  document.querySelectorAll("[data-circle-create]").forEach(button => {
    button.addEventListener("click", () => {
      circleForm.action.value = "create_circle";
      circleForm.id.value = "";
      circleForm.title.textContent = "إضافة دائرة جديدة";
      circleForm.side.value = "";
      circleForm.name.value = "";
      circleForm.slug.value = "";
      circleForm.file.value = "";
      circleForm.badge.value = "";
      circleForm.sort.value = "0";
      if (circleForm.currentPreview) circleForm.currentPreview.hidden = true;
      if (circleForm.currentImage) circleForm.currentImage.removeAttribute("src");
      if (circleForm.fileLabel) circleForm.fileLabel.textContent = "صورة الدائرة";
      const sideId = new URLSearchParams(window.location.search).get("side_category_id");
      if (sideId) circleForm.side.value = sideId;
      open(circleModal);
    });
  });

  document.querySelectorAll("[data-circle-edit]").forEach(button => {
    button.addEventListener("click", () => {
      const circleId = Number(button.dataset.circleEdit);
      const row = items.flatMap(x => x.circles || []).find(x => Number(x.id) === circleId);
      if (!row) return;
      circleForm.action.value = "update_circle";
      circleForm.id.value = String(row.id);
      circleForm.title.textContent = "تعديل دائرة التصنيف";
      circleForm.side.value = String(row.side_category_id);
      circleForm.name.value = row.name || "";
      circleForm.slug.value = row.slug || "";
      circleForm.file.value = "";
      circleForm.badge.value = String(row.badge_id || "");
      circleForm.sort.value = String(row.sort_order || 0);
      if (circleForm.currentImage) {
        circleForm.currentImage.src = row.image_url || "";
      }
      if (circleForm.currentPreview) {
        circleForm.currentPreview.hidden = !row.image_url;
      }
      if (circleForm.fileLabel) circleForm.fileLabel.textContent = row.image_url ? "استبدال صورة الدائرة" : "صورة الدائرة";
      open(circleModal);
    });
  });

  document.querySelectorAll("[data-side-close]").forEach(button => {
    button.addEventListener("click", () => {
      close(sideModal);
      close(circleModal);
    });
  });

  document.addEventListener("keydown", event => {
    if (event.key !== "Escape") return;
    close(sideModal);
    close(circleModal);
  });

  const filter = document.getElementById("sideCircleFilter");
  if (filter) {
    filter.addEventListener("change", () => {
      const params = new URLSearchParams(window.location.search);
      params.set("view", "circles");
      if (filter.value) params.set("side_category_id", filter.value);
      else params.delete("side_category_id");
      window.location.search = params.toString();
    });
  }
  circleForm.file?.addEventListener("change", () => {
    if (!circleForm.file.files?.length) return;
    if (circleForm.fileLabel) circleForm.fileLabel.textContent = "الصورة الجديدة: " + circleForm.file.files[0].name;
    if (circleForm.currentImage) {
      const url = URL.createObjectURL(circleForm.file.files[0]);
      circleForm.currentImage.src = url;
      if (circleForm.currentPreview) circleForm.currentPreview.hidden = false;
      circleForm.currentImage.onload = () => URL.revokeObjectURL(url);
    }
  });
})();

(function(){
  "use strict";
  const $=(s,r=document)=>r.querySelector(s);
  const $$=(s,r=document)=>Array.from(r.querySelectorAll(s));
  const norm=(value)=>String(value||"").toLocaleLowerCase("ar").normalize("NFKD").replace(/[\u064B-\u065F\u0670]/g,"").trim();

  function collapseNode(node){
    const children=$(":scope > [data-account-children]",node);
    if(!children)return;
    children.hidden=true;
    const toggle=$(":scope > .account-picker-row [data-account-toggle]",node);
    if(toggle){toggle.setAttribute("aria-expanded","false");const icon=$("i",toggle);if(icon)icon.className="bi bi-chevron-left";}
    $$("[data-account-node]",children).forEach(collapseNode);
  }
  function openNode(node){
    const parentChildren=node.parentElement;
    if(parentChildren){
      $$(":scope > [data-account-node]",parentChildren).forEach(sibling=>{if(sibling!==node)collapseNode(sibling);});
    }
    const children=$(":scope > [data-account-children]",node);
    const toggle=$(":scope > .account-picker-row [data-account-toggle]",node);
    if(children){children.hidden=false;if(toggle){toggle.setAttribute("aria-expanded","true");const icon=$("i",toggle);if(icon)icon.className="bi bi-chevron-down";}}
  }
  function initPicker(picker){
    if(picker.dataset.accountPickerReady==="1")return;
    picker.dataset.accountPickerReady="1";
    const trigger=$("[data-account-trigger]",picker);
    const panel=$("[data-account-panel]",picker);
    const search=$("[data-account-search]",picker);
    const searchButton=$("[data-account-search-submit]",picker);
    const hidden=$("[data-account-value]",picker);
    const label=$("[data-account-label]",picker);
    const noResults=$("[data-account-no-results]",picker);
    const clear=$("[data-account-clear]",picker);
    const mode=picker.dataset.pickerMode||"select";
    const nodes=$$(":scope > .account-picker-node", $("[data-account-tree]",picker)||picker);
    function getNodes(){return $$("[data-account-node]",picker);}
    function show(open){
      if(!panel||!trigger)return;
      panel.hidden=!open;
      picker.classList.toggle("is-open",open);
      trigger.setAttribute("aria-expanded",String(open));
      if(open){setTimeout(()=>search?.focus(),25);}
      else if(search&&search.value) {
        search.value="";
        filterTree();
      }
    }
    function filterTree(){
      const q=norm(search?.value);
      const list=getNodes();
      function visit(node){
        const own=norm(node.dataset.accountSearch).includes(q);
        const children=$(":scope > [data-account-children]",node);
        let descendant=false;
        if(children){
          $$(":scope > [data-account-node]",children).forEach(child=>{if(visit(child))descendant=true;});
        }
        const visible=!q||own||descendant;
        node.hidden=!visible;
        if(children){
          if(q&&descendant){children.hidden=false;const btn=$(":scope > .account-picker-row [data-account-toggle]",node);if(btn){btn.setAttribute("aria-expanded","true");const icon=$("i",btn);if(icon)icon.className="bi bi-chevron-down";}}
          else if(!q){collapseNode(node);}
          else if(!descendant){children.hidden=true;}
        }
        return visible;
      }
      $$(":scope > .account-picker-node",$("[data-account-tree]",picker)).forEach(visit);
      if(noResults)noResults.hidden=list.some(n=>!n.hidden);
    }
    $$("[data-account-toggle]",picker).forEach(button=>{
      button.addEventListener("click",event=>{
        event.stopPropagation();
        const node=button.closest("[data-account-node]");
        const children=$(":scope > [data-account-children]",node);
        if(!children)return;
        if(children.hidden)openNode(node);else collapseNode(node);
      });
    });
    $$("[data-account-select]",picker).forEach(button=>{
      button.addEventListener("click",()=>{
        if(mode==="navigate"){
          const href=button.dataset.accountHref;
          if(href)window.location.assign(href);
          return;
        }
        if(hidden)hidden.value=button.dataset.value||"";
        if(label)label.textContent=button.dataset.label||button.textContent.trim();
        picker.classList.add("has-selection");
        show(false);
        hidden?.dispatchEvent(new Event("change",{bubbles:true}));
      });
    });
    $$("[data-account-open]",picker).forEach(button=>button.addEventListener("click",()=>{
      if(button.dataset.accountHref)window.location.assign(button.dataset.accountHref);
    }));
    trigger?.addEventListener("click",event=>{event.stopPropagation();show(panel?.hidden!==false);});
    search?.addEventListener("input",filterTree);
    searchButton?.addEventListener("click",filterTree);
    search?.addEventListener("keydown",event=>{
      if(event.key==="Enter"){event.preventDefault();filterTree();}
      if(event.key==="Escape")show(false);
    });
    clear?.addEventListener("click",()=>{
      if(hidden)hidden.value="";
      if(label)label.textContent=picker.dataset.placeholder||"اختر الحساب";
      picker.classList.remove("has-selection");
      show(false);
      hidden?.dispatchEvent(new Event("change",{bubbles:true}));
    });
    document.addEventListener("click",event=>{if(!picker.contains(event.target))show(false);});
    document.addEventListener("keydown",event=>{if(event.key==="Escape"&&panel&&!panel.hidden)show(false);});
    // Keep tree folded on first load like Kareem's account picker.
    getNodes().forEach(node=>{const children=$(":scope > [data-account-children]",node);if(children)children.hidden=true;});
  }
  function initAccountPickers(){ $$("[data-account-picker]").forEach(initPicker); }
  document.addEventListener("DOMContentLoaded",initAccountPickers);
  initAccountPickers();



  function initCustomerPicker(picker){
    if(picker.dataset.customerPickerReady==="1")return;
    picker.dataset.customerPickerReady="1";
    const trigger=$("[data-customer-trigger]",picker),panel=$("[data-customer-panel]",picker);
    const search=$("[data-customer-search]",picker),searchButton=$("[data-customer-search-submit]",picker);
    const hidden=$("[data-customer-value]",picker),label=$("[data-customer-label]",picker);
    const empty=$("[data-customer-no-results]",picker),clear=$("[data-customer-clear]",picker);
    const options=$$("[data-customer-option]",picker);
    function show(open){if(!panel||!trigger)return;panel.hidden=!open;picker.classList.toggle("is-open",open);trigger.setAttribute("aria-expanded",String(open));if(open)setTimeout(()=>search?.focus(),25);else if(search)search.value="";}
    function filter(){
      const q=norm(search?.value);
      let visible=0;
      options.forEach(option=>{const ok=!q||norm(option.dataset.customerSearch||option.textContent).includes(q);option.hidden=!ok;if(ok)visible++;});
      if(empty)empty.hidden=visible>0;
    }
    trigger?.addEventListener("click",event=>{event.stopPropagation();show(panel?.hidden!==false);});
    options.forEach(option=>option.addEventListener("click",()=>{
      if(hidden)hidden.value=option.dataset.customerId||"";
      if(label)label.textContent=option.dataset.customerLabel||option.textContent.trim();
      picker.classList.add("has-selection");
      show(false);
      hidden?.dispatchEvent(new Event("change",{bubbles:true}));
    }));
    search?.addEventListener("input",filter);
    searchButton?.addEventListener("click",filter);
    search?.addEventListener("keydown",event=>{if(event.key==="Enter"){event.preventDefault();filter();}if(event.key==="Escape")show(false);});
    clear?.addEventListener("click",()=>{
      if(hidden)hidden.value="";
      if(label)label.textContent=picker.dataset.placeholder||"اختر العميل";
      picker.classList.remove("has-selection");show(false);
      hidden?.dispatchEvent(new Event("change",{bubbles:true}));
    });
    document.addEventListener("click",event=>{if(!picker.contains(event.target))show(false);});
    document.addEventListener("keydown",event=>{if(event.key==="Escape"&&panel&&!panel.hidden)show(false);});
  }
  function initCustomerPickers(){ $$("[data-customer-picker]").forEach(initCustomerPicker); }
  document.addEventListener("DOMContentLoaded",initCustomerPickers);
  initCustomerPickers();

  const ones=["صفر","واحد","اثنان","ثلاثة","أربعة","خمسة","ستة","سبعة","ثمانية","تسعة"];
  const teens=["عشرة","أحد عشر","اثنا عشر","ثلاثة عشر","أربعة عشر","خمسة عشر","ستة عشر","سبعة عشر","ثمانية عشر","تسعة عشر"];
  const tens=["","","عشرون","ثلاثون","أربعون","خمسون","ستون","سبعون","ثمانون","تسعون"];
  const hundreds=["","مائة","مائتان","ثلاثمائة","أربعمائة","خمسمائة","ستمائة","سبعمائة","ثمانمائة","تسعمائة"];
  function underThousand(n){
    n=Math.floor(n);
    if(n===0)return "";
    const parts=[];const h=Math.floor(n/100),r=n%100;
    if(h)parts.push(hundreds[h]);
    if(r>=10&&r<20)parts.push(teens[r-10]);
    else{
      const u=r%10,t=Math.floor(r/10);
      if(u&&t)parts.push(ones[u]+" و"+tens[t]);
      else if(u)parts.push(ones[u]);
      else if(t)parts.push(tens[t]);
    }
    return parts.join(" و");
  }
  function intWords(n){
    n=Math.floor(Math.abs(n));
    if(n===0)return ones[0];
    const units=[{v:1e12,s:"تريليون",d:"تريليون"},{v:1e9,s:"مليار",d:"مليار"},{v:1e6,s:"مليون",d:"مليون"},{v:1e3,s:"ألف",d:"ألف"}];
    const parts=[];
    for(const unit of units){const q=Math.floor(n/unit.v);if(q){let text=underThousand(q);if(q===1)text=unit.s;else if(q===2)text=unit.s+"ان";else text=text+" "+unit.d;parts.push(text);n%=unit.v;}}
    if(n)parts.push(underThousand(n));
    return parts.join(" و");
  }
  window.moneyToArabicWords=function(value,currency){
    const raw=String(value??"").replace(/,/g,"").trim();
    if(!raw)return "";
    const amount=Number(raw);
    if(!Number.isFinite(amount)||amount<0)return "";
    const whole=Math.floor(amount), fractional=Math.round((amount-whole)*100);
    const code=(currency||"YER").toUpperCase();
    const currencyNames={YER:"ريال يمني",SAR:"ريال سعودي",USD:"دولار أمريكي",EUR:"يورو",AED:"درهم إماراتي",KWD:"دينار كويتي",QAR:"ريال قطري",OMR:"ريال عماني",BHD:"دينار بحريني",EGP:"جنيه مصري",GBP:"جنيه إسترليني",TRY:"ليرة تركية"};
    const currencyLabel=currencyNames[code]||("عملة "+code);
    let text=intWords(whole)+" "+currencyLabel;
    if(fractional)text+=" و"+intWords(fractional)+" فلس";
    return text+" فقط لا غير";
  };
  function initAmountWords(){
    $$("[data-money-words]").forEach(input=>{
      if(input.dataset.wordsReady==="1")return;input.dataset.wordsReady="1";
      const target=$(input.dataset.moneyWordsTarget);
      const currency=input.dataset.moneyCurrency||"YER";
      const update=()=>{if(target)target.textContent=window.moneyToArabicWords(input.value,currency);};
      input.addEventListener("input",update);update();
    });
  }
  document.addEventListener("DOMContentLoaded",initAmountWords);
  initAmountWords();
})();
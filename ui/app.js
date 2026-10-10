// Homepage's tabs on the chassis window: Dashboard, Look, Synology stats, Edit by hand.
(function (P) {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var COLORS = { slate: "#475569", gray: "#4b5563", zinc: "#52525b", stone: "#57534e", red: "#dc2626", orange: "#ea580c", amber: "#d97706", yellow: "#ca8a04", lime: "#65a30d", green: "#16a34a",
    emerald: "#059669", teal: "#0d9488", cyan: "#0891b2", sky: "#0284c7", blue: "#2563eb", indigo: "#4f46e5", violet: "#7c3aed", purple: "#9333ea", fuchsia: "#c026d3", pink: "#db2777", rose: "#e11d48" };
  var ICON_CDN = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/";   // the icons Homepage itself uses for name.png
  function hpUrl(st) { return ((st.app || {}).url || "").replace(/\/$/, ""); }
  function touched(id) { ["input", "change"].forEach(function (e) { $(id).addEventListener(e, function () { $(id).dataset.touched = "1"; }); }); }
  function quiet(id, v) { if (!$(id).dataset.touched) { if ($(id).type === "checkbox") $(id).checked = !!v; else $(id).value = v == null ? "" : v; } }

  // ---------------------------------------------------------------- Dashboard
  P.register("dashboard", {
    render: function (st) {
      var a = st.app || {}, found = a.found || [], links = (a.links || []).map(function (l) { return Object.assign({ link: true }, l); }), hidden = a.hidden || [];
      document.querySelectorAll(".hp-link").forEach(function (x) { x.href = hpUrl(st) || "#"; });
      var all = found.concat(links), shown = all.filter(function (x) { return hidden.indexOf(x.key) < 0; }), t = $("db-tiles");
      P.clear(t); P.tile(t, String(shown.length), "tiles on the dashboard"); P.tile(t, String(found.filter(function (x) { return x.group === "Apps"; }).length), "apps found");
      P.tile(t, String(found.filter(function (x) { return x.group === "Containers"; }).length), "other containers"); P.tile(t, String(links.length), "your links");
      $("db-when").textContent = a.found_at ? "Last looked " + P.ago(a.found_at) + "." : "";
      var tb = $("db-items"), sig = JSON.stringify([all, hidden, a.manual]) + "|" + P.busy + "|" + P.role; if (tb.dataset.sig === sig) return; tb.dataset.sig = sig; P.clear(tb);
      if (a.manual) { var r0 = P.el("tr"), c0 = P.cell("You're editing the YAML by hand, so the package isn't changing the dashboard (see Edit by hand).", "empty"); c0.colSpan = 4; r0.appendChild(c0); tb.appendChild(r0); }
      all.forEach(function (x) {
        var off = hidden.indexOf(x.key) >= 0, who = P.el("div"), img = P.el("img"); img.className = "tile-icon"; img.alt = "";
        if (x.icon && /\.png$/.test(x.icon)) img.src = ICON_CDN + x.icon; else img.style.visibility = "hidden";
        img.onerror = function () { img.style.visibility = "hidden"; };
        who.appendChild(img); who.appendChild(document.createTextNode(x.name));
        if (x.widget) who.appendChild(P.el("span", "  live numbers", "muted small"));
        var acts = P.el("span", null, "row");
        acts.appendChild(P.btn(off ? "Show" : "Hide", "", function () { P.act("toggle", { item: x.key, hide: off ? 0 : 1 }); }));
        if (x.link) acts.appendChild(P.btn("Remove", "danger", function () { P.act("linkdel", { item: x.key }, "Remove the link " + x.name + "?"); }));
        var addr = P.el("a", x.href, "href"); addr.href = x.href; addr.target = "_blank"; addr.rel = "noopener";
        var tr = P.row(tb, [P.cell(who), x.group, P.cell(addr), P.cell(acts, "n")]); if (off) tr.className = "muted-row";
      });
    }
  });
  $("ln-add").onclick = function () {
    P.act("linkadd", { name: $("ln-name").value.trim(), url: $("ln-url").value.trim(), group: $("ln-group").value.trim(), icon: $("ln-icon").value.trim() })
      .then(function () { ["ln-name", "ln-url", "ln-icon"].forEach(function (id) { $(id).value = ""; }); });
  };

  // ---------------------------------------------------------------- Look
  var color = "slate";
  function swatches(sel) {
    var box = $("lk-colors"); P.clear(box);
    Object.keys(COLORS).forEach(function (k) { var s = P.el("span", null, "swatch" + (k === sel ? " on" : "")); s.style.background = COLORS[k]; s.title = k; s.onclick = function () { color = k; $("lk-colors").dataset.touched = "1"; swatches(k); }; box.appendChild(s); });
  }
  ["lk-title", "lk-theme", "lk-search", "lk-clock"].forEach(touched);
  P.register("look", {
    render: function (st) {
      var a = st.app || {}; quiet("lk-title", a.title); quiet("lk-theme", a.theme || "dark"); quiet("lk-search", a.search !== false); quiet("lk-clock", a.clock !== false);
      if (!$("lk-colors").dataset.touched && $("lk-colors").dataset.sel !== a.color) { color = a.color || "slate"; $("lk-colors").dataset.sel = color; swatches(color); }
    }
  });
  $("lk-save").onclick = function () {
    P.act("look", { title: $("lk-title").value.trim(), theme: $("lk-theme").value, color: color, search: $("lk-search").checked ? 1 : 0, clock: $("lk-clock").checked ? 1 : 0 })
      .then(function () { ["lk-title", "lk-theme", "lk-search", "lk-clock", "lk-colors"].forEach(function (id) { $(id).dataset.touched = ""; }); });
  };

  // ---------------------------------------------------------------- Synology stats
  ["ds-user", "ds-vol"].forEach(touched);
  P.register("dsmstats", {
    render: function (st) {
      var d = (st.app || {}).dsm || {}, t = $("ds-tiles"); P.clear(t);
      P.tile(t, d.user ? "on" : "off", d.user ? "stats, as " + d.user : "stats on the DSM tile");
      quiet("ds-user", d.user); quiet("ds-vol", d.volume);
    }
  });
  function dsBody() { return { user: $("ds-user").value.trim(), pass: $("ds-pass").value, volume: $("ds-vol").value.trim() }; }
  $("ds-test").onclick = function () { P.act("dsmtest", dsBody()); };
  $("ds-save").onclick = function () { P.act("dsmset", dsBody()).then(function () { $("ds-pass").value = ""; ["ds-user", "ds-vol"].forEach(function (id) { $(id).dataset.touched = ""; }); }); };

  // ---------------------------------------------------------------- Edit by hand
  P.register("byhand", {
    render: function (st) {
      var a = st.app || {}; $("bh-dir").textContent = a.config_dir || "homepage/config";
      $("bh-state").textContent = a.manual ? "You're editing the YAML by hand. The package leaves it alone." : "The package writes the YAML from this window (and from what it finds).";
      $("bh-on").disabled = !!a.manual || P.role !== "admin" || P.busy; $("bh-off").disabled = !a.manual || P.role !== "admin" || P.busy;
    }
  });
  $("bh-on").onclick = function () { P.act("manual", { on: 1 }, "Take over the YAML? The package stops changing the dashboard."); };
  $("bh-off").onclick = function () { P.act("manual", { on: 0 }, "Let the package write the dashboard again? Your hand edits to services.yaml, settings.yaml and widgets.yaml are replaced."); };

  // ---------------------------------------------------------------- Storage
  P.register("storage", { render: function (app, st, box) {
    P.clear(box); var c = P.el("div", null, "card"); c.appendChild(P.el("h2", "In the homepage shared folder")); var tbl = P.el("table"), tb = P.el("tbody"); tbl.appendChild(tb); c.appendChild(tbl);
    [["config (the YAML files)", app.config], ["images (backgrounds, your icons)", app.images]].forEach(function (p) { P.kv(tb, p[0], P.mb(p[1] || 0), true); });
    box.appendChild(c);
  } });
})(window.Panel);

// Halcyon website: live clock, the + sheet, and download links from the latest release.
(() => {
  const repo = "__REPO__";

  // Phone clock.
  const clock = document.getElementById("clock");
  const tick = () => {
    if (!clock) return;
    const now = new Date();
    clock.textContent = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }).replace(/\s?[AP]M$/i, "");
  };
  tick();
  setInterval(tick, 15000);

  // The + button explains itself in a sheet.
  const sheet = document.getElementById("sheet");
  const plus = document.getElementById("plus");
  const close = document.getElementById("sheet-close");
  const setSheet = (open) => {
    if (!sheet) return;
    if (open) {
      sheet.hidden = false;
      requestAnimationFrame(() => (sheet.dataset.open = "true"));
      close && close.focus();
    } else {
      sheet.dataset.open = "false";
      setTimeout(() => (sheet.hidden = true), 320);
      plus && plus.focus();
    }
  };
  plus && plus.addEventListener("click", () => setSheet(sheet.hidden));
  close && close.addEventListener("click", () => setSheet(false));
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && sheet && !sheet.hidden) setSheet(false);
  });

  // Point the download buttons at the newest release's files (pre-releases included).
  if (repo.includes("__")) return;
  fetch(`https://api.github.com/repos/${repo}/releases?per_page=5`, { headers: { Accept: "application/vnd.github+json" } })
    .then((r) => (r.ok ? r.json() : []))
    .then((releases) => {
      const release = releases.find((r) => !r.draft && r.assets.some((a) => a.name.endsWith(".ipa") || a.name.endsWith(".dmg")));
      if (!release) return;
      const asset = (ext) => release.assets.find((a) => a.name.endsWith(ext));
      const ipa = asset(".ipa");
      const dmg = asset(".dmg");
      const mb = (a) => `${(a.size / 1048576).toFixed(0)} MB`;
      if (ipa) {
        for (const id of ["dl-ipa", "tile-ipa"]) document.getElementById(id).href = ipa.browser_download_url;
      }
      if (dmg) {
        for (const id of ["dl-dmg", "tile-dmg"]) document.getElementById(id).href = dmg.browser_download_url;
      }
      const line = document.getElementById("release-line");
      if (line) {
        const date = new Date(release.published_at).toLocaleDateString([], { year: "numeric", month: "long", day: "numeric" });
        const sizes = [ipa && `iPhone ${mb(ipa)}`, dmg && `Mac ${mb(dmg)}`].filter(Boolean).join(", ");
        line.textContent = `Version ${release.tag_name.replace(/^v/, "")}${release.prerelease ? " (preview)" : ""}, released ${date}. ${sizes}.`;
      }
    })
    .catch(() => {});
})();

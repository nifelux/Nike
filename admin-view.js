// LAS-VEGAS-compatible admin viewing helper for Nike Investor multi-page screens.
export function resolveEffectiveUser() {
  return new URLSearchParams(window.location.search).get("view_as");
}
export function injectAdminBanner() {
  const id = resolveEffectiveUser();
  if (!id) return;
  const banner = document.createElement("div");
  banner.style.cssText = "position:fixed;bottom:0;left:0;right:0;z-index:100;background:#090909;color:#fff;padding:10px 18px;font:600 11px 'IBM Plex Mono',monospace;letter-spacing:.08em;text-align:center";
  banner.textContent = "ADMIN VIEWING INVESTOR CONTEXT // " + id;
  document.body.appendChild(banner);
}
export async function adminCall(resource, action, body = {}) {
  const response = await fetch("/api/admin?resource=" + encodeURIComponent(resource) + "&action=" + encodeURIComponent(action), { method:"POST", headers:{ "Content-Type":"application/json" }, body:JSON.stringify(body) });
  return response.json();
}

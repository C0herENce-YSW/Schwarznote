// Runs inside the Xiaohongshu / rednote page. Sends the request through the site's own
// HTTP client so every interceptor adds its headers (X-s, X-t, X-S-Common, trace ids …),
// records them, and aborts the XHR before anything leaves the browser.
async ({ method, path, body }) => {
  if (!window.__signerHttp) {
    const chunk = Object.keys(window).find((k) => k.startsWith("webpackChunk"));
    let require;
    window[chunk].push([[Symbol("signer")], {}, (r) => { require = r; }]);
    // The site's shared HTTP client, exported from its request module as `LV`.
    window.__signerHttp = Object.values(require.c)
      .map((m) => m && m.exports && m.exports.LV)
      .find((http) => http && typeof http.post === "function" && http.interceptors);
    if (!window.__signerHttp) throw new Error("site HTTP client not found");
  }

  const proto = XMLHttpRequest.prototype;
  const original = { open: proto.open, setRequestHeader: proto.setRequestHeader, send: proto.send };
  const restore = () => Object.assign(proto, original);

  try {
    return await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("timed out waiting for the request")), 10000);
      proto.open = function (m, url) {
        this.__signerURL = String(url);
        return original.open.apply(this, arguments);
      };
      proto.setRequestHeader = function (key, value) {
        (this.__signerHeaders ||= {})[key] = String(value);
        return original.setRequestHeader.apply(this, arguments);
      };
      proto.send = function () {
        clearTimeout(timer);
        restore();
        resolve({ url: this.__signerURL, headers: this.__signerHeaders || {} });
        this.abort();
      };
      const http = window.__signerHttp;
      const request = method === "GET" ? http.get(path) : http.post(path, body);
      request.catch(() => {}); // rejected by our abort
    });
  } finally {
    restore();
  }
}

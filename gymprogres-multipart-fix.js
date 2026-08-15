(function () {
  'use strict';

  // Flutter Web + Dio: when FormData is uploaded, the browser must create the
  // multipart Content-Type together with its boundary. The current compiled
  // client tries to set only "multipart/form-data", which can make the browser
  // request fail before FastAPI receives it.
  if (typeof XMLHttpRequest !== 'undefined') {
    const originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
      if (
        typeof name === 'string' &&
        name.toLowerCase() === 'content-type' &&
        typeof value === 'string' &&
        value.trim().toLowerCase() === 'multipart/form-data'
      ) {
        return;
      }
      return originalSetRequestHeader.call(this, name, value);
    };
  }

  // Keep the same safeguard if a future Dio Web adapter switches to fetch().
  if (typeof window.fetch === 'function') {
    const originalFetch = window.fetch.bind(window);
    window.fetch = function (input, init) {
      if (init && init.body instanceof FormData && init.headers) {
        const headers = new Headers(init.headers);
        headers.delete('Content-Type');
        headers.delete('content-type');
        init = Object.assign({}, init, { headers: headers });
      }
      return originalFetch(input, init);
    };
  }
})();

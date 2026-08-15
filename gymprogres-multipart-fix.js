(function () {
  'use strict';

  function isExcelUploadUrl(value) {
    const url = String(value || '');
    return (
      url.includes('/api/v1/plans/import/excel') ||
      url.includes('/api/v1/plans/library/import/excel')
    );
  }

  // Flutter Web + Dio uses XMLHttpRequest in the current production build.
  // ApiClient has a global "Content-Type: application/json" header and the
  // Excel upload also used to force "multipart/form-data" manually. Either
  // value is wrong for a browser FormData upload because the browser itself
  // must create: multipart/form-data; boundary=...
  if (typeof XMLHttpRequest !== 'undefined') {
    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;

    XMLHttpRequest.prototype.open = function (method, url) {
      this.__gymprogresExcelUpload = isExcelUploadUrl(url);
      return originalOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
      if (
        this.__gymprogresExcelUpload === true &&
        typeof name === 'string' &&
        name.toLowerCase() === 'content-type'
      ) {
        // Do not send application/json or a boundary-less multipart header.
        // XMLHttpRequest will generate the correct multipart header from
        // FormData when send(FormData) is called.
        return;
      }
      return originalSetRequestHeader.call(this, name, value);
    };
  }

  // Future-proof the same fix for a possible fetch-based Dio adapter.
  if (typeof window.fetch === 'function') {
    const originalFetch = window.fetch.bind(window);
    window.fetch = function (input, init) {
      const requestUrl = typeof input === 'string' ? input : (input && input.url);
      if (
        isExcelUploadUrl(requestUrl) &&
        init &&
        typeof FormData !== 'undefined' &&
        init.body instanceof FormData
      ) {
        const headers = new Headers(init.headers || {});
        headers.delete('Content-Type');
        headers.delete('content-type');
        init = Object.assign({}, init, { headers: headers });
      }
      return originalFetch(input, init);
    };
  }
})();

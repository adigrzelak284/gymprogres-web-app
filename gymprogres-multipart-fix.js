(function () {
  'use strict';

  function isExcelUploadUrl(value) {
    const url = String(value || '');
    return (
      url.includes('/api/v1/plans/import/excel') ||
      url.includes('/api/v1/plans/library/import/excel')
    );
  }

  // The current Flutter Web build uses Dio's XMLHttpRequest adapter. Dio does
  // NOT send a native browser FormData object here: it serializes FormData to
  // bytes and then sets the final multipart header itself, including boundary.
  // Therefore we must preserve:
  //   multipart/form-data; boundary=...
  // and suppress only stale/invalid Content-Type values for Excel uploads.
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
        const normalized = String(value || '').trim().toLowerCase();
        const hasMultipartBoundary =
          normalized.startsWith('multipart/form-data;') &&
          normalized.includes('boundary=');

        if (hasMultipartBoundary) {
          return originalSetRequestHeader.call(this, name, value);
        }

        if (
          normalized === 'multipart/form-data' ||
          normalized.startsWith('application/json')
        ) {
          return;
        }
      }
      return originalSetRequestHeader.call(this, name, value);
    };
  }

  // If a future adapter sends a native FormData with fetch(), let the browser
  // create its own boundary. This branch does not affect today's Dio XHR build.
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

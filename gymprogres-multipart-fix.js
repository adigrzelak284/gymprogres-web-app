(function () {
  'use strict';

  function isExcelUploadUrl(value) {
    const url = String(value || '');
    return (
      url.includes('/api/v1/plans/import/excel') ||
      url.includes('/api/v1/plans/library/import/excel')
    );
  }

  // Current Flutter Web + Dio serializes FormData to multipart bytes before
  // XMLHttpRequest sends the request. Chrome is more reliable for this build
  // when Content-Type is not manually attached to the cross-origin request.
  // API 33.8.8 recovers the multipart boundary directly from the serialized
  // body for the two Excel endpoints, so suppress every Content-Type value
  // here while preserving Authorization and GymProgres headers.
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
        return;
      }
      return originalSetRequestHeader.call(this, name, value);
    };
  }

  // Future fetch-based adapter: native FormData also needs Content-Type left to
  // the browser. This branch does not affect the current Dio XHR build.
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

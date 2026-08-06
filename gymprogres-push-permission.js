(function () {
  'use strict';

  var containerId = 'gymprogres-push-permission-box';

  function removeBox() {
    var existing = document.getElementById(containerId);
    if (existing) existing.remove();
  }

  function createBox() {
    if (!('Notification' in window)) return;
    if (Notification.permission !== 'default') return;
    if (document.getElementById(containerId)) return;

    var box = document.createElement('div');
    box.id = containerId;
    box.setAttribute('role', 'status');
    box.style.position = 'fixed';
    box.style.right = '18px';
    box.style.bottom = '18px';
    box.style.zIndex = '2147483647';
    box.style.maxWidth = '340px';
    box.style.padding = '14px';
    box.style.borderRadius = '14px';
    box.style.background = '#101827';
    box.style.color = '#ffffff';
    box.style.border = '1px solid rgba(56, 189, 248, 0.45)';
    box.style.boxShadow = '0 12px 34px rgba(0, 0, 0, 0.35)';
    box.style.fontFamily = 'Arial, sans-serif';

    var title = document.createElement('div');
    title.textContent = 'Powiadomienia GymProgres';
    title.style.fontWeight = '700';
    title.style.marginBottom = '6px';

    var description = document.createElement('div');
    description.textContent = 'W┼é─ůcz powiadomienia, aby otrzymywa─ç nowe wiadomo┼Ťci tak┼╝e wtedy, gdy karta jest w tle.';
    description.style.fontSize = '13px';
    description.style.lineHeight = '1.4';
    description.style.opacity = '0.86';
    description.style.marginBottom = '12px';

    var actions = document.createElement('div');
    actions.style.display = 'flex';
    actions.style.gap = '8px';
    actions.style.justifyContent = 'flex-end';

    var later = document.createElement('button');
    later.type = 'button';
    later.textContent = 'P├│┼║niej';
    later.style.padding = '8px 12px';
    later.style.borderRadius = '9px';
    later.style.border = '1px solid rgba(255, 255, 255, 0.18)';
    later.style.background = 'transparent';
    later.style.color = '#ffffff';
    later.style.cursor = 'pointer';
    later.addEventListener('click', removeBox);

    var enable = document.createElement('button');
    enable.type = 'button';
    enable.textContent = 'W┼é─ůcz powiadomienia';
    enable.style.padding = '8px 12px';
    enable.style.borderRadius = '9px';
    enable.style.border = '0';
    enable.style.background = '#38bdf8';
    enable.style.color = '#04111d';
    enable.style.fontWeight = '700';
    enable.style.cursor = 'pointer';
    enable.addEventListener('click', async function () {
      enable.disabled = true;
      try {
        var permission = await Notification.requestPermission();
        removeBox();
        if (permission === 'granted') {
          window.location.reload();
        }
      } catch (error) {
        console.warn('[GYMPROGRES_PUSH] permission request failed', error);
        enable.disabled = false;
      }
    });

    actions.appendChild(later);
    actions.appendChild(enable);
    box.appendChild(title);
    box.appendChild(description);
    box.appendChild(actions);
    document.body.appendChild(box);
  }

  window.addEventListener('load', function () {
    window.setTimeout(createBox, 1500);
  });
})();

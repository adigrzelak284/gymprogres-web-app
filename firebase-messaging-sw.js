importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyBZgMYSwyAjz4JyXWeCia84o8gdguPry5A",
  authDomain: "gymprogres-7bad7.firebaseapp.com",
  projectId: "gymprogres-7bad7",
  storageBucket: "gymprogres-7bad7.firebasestorage.app",
  messagingSenderId: "911927557870",
  appId: "1:911927557870:web:a26ac417080e7d12693dff"
});

const messaging = firebase.messaging();

self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});

messaging.onBackgroundMessage(function(payload) {
  const notification = payload && payload.notification ? payload.notification : {};
  const data = payload && payload.data ? payload.data : {};
  const title = notification.title || data.title || 'GymProgres';
  const body = notification.body || data.body || 'Nowa wiadomosc';
  const icon = '/icons/Icon-192.png';
  const badge = '/icons/Icon-192.png';
  const clickAction = data.click_action || data.clickAction || '/';

  const options = {
    body: body,
    icon: icon,
    badge: badge,
    data: {
      click_action: clickAction,
      url: clickAction
    },
    requireInteraction: false,
    tag: data.tag || 'gymprogres-message'
  };

  return self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const targetUrl = (event.notification.data && (event.notification.data.url || event.notification.data.click_action)) || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      for (let i = 0; i < clientList.length; i++) {
        const client = clientList[i];
        if ('focus' in client) {
          client.postMessage({ type: 'gymprogres-notification-click', url: targetUrl });
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});

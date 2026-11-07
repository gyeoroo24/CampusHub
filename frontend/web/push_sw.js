// Web Push service worker (FR-22). Shows the notifications the CampusHub server pushes, and opens the
// right page when one is tapped. Registered by push.js under its own scope, so it never intercepts the
// app's page loads (Flutter's own service worker, if any, keeps the root scope).

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  const title = data.title || 'CampusHub';
  event.waitUntil(self.registration.showNotification(title, {
    body: data.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: data.tag || undefined,          // one visible notification per kind; a newer one replaces it
    renotify: Boolean(data.tag),
    data: { url: data.url || '/' },
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = new URL(event.notification.data && event.notification.data.url || '/', self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if (new URL(client.url).origin === self.location.origin && 'focus' in client) {
        // The app page isn't controlled by this worker, so it can't be navigated from here: ask it to
        // go to the page itself (push.js), which keeps the app running instead of reloading it.
        client.postMessage({ type: 'campushub-open', url: target });
        await client.focus();
        return;
      }
    }
    await self.clients.openWindow(target);
  })());
});

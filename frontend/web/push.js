// Web Push helpers for the Flutter app (lib/core/push/web_push_web.dart calls these). FR-22.
// Every function resolves (never rejects) so the Dart side only has to handle plain values.
(function () {
  const SW_URL = '/push_sw.js';
  const SW_SCOPE = '/push-notifications/';   // its own scope: it shows pushes, it doesn't serve pages

  function supported() {
    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  }

  function keyBytes(base64url) {
    const padded = (base64url + '='.repeat((4 - base64url.length % 4) % 4)).replace(/-/g, '+').replace(/_/g, '/');
    return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
  }

  async function registration() {
    return navigator.serviceWorker.register(SW_URL, { scope: SW_SCOPE });
  }

  // A notification was tapped while the app was open: go to its page inside the running app.
  if (supported()) {
    navigator.serviceWorker.addEventListener('message', (event) => {
      const data = event.data || {};
      if (data.type !== 'campushub-open' || !data.url) return;
      const url = new URL(data.url, location.origin);
      if (url.origin !== location.origin) return;
      history.pushState({}, '', url.pathname + url.search);
      window.dispatchEvent(new PopStateEvent('popstate', { state: {} }));
    });
  }

  window.campushubPush = {
    // 'unsupported' | 'default' | 'granted' | 'denied'
    permission() {
      return supported() ? Notification.permission : 'unsupported';
    },

    // Asks for permission if needed and subscribes. Resolves to the subscription's JSON, or '' if the
    // browser can't, or the person said no.
    async subscribe(publicKey) {
      try {
        if (!supported()) return '';
        const permission = Notification.permission === 'granted'
          ? 'granted' : await Notification.requestPermission();
        if (permission !== 'granted') return '';
        const reg = await registration();
        let sub = await reg.pushManager.getSubscription();
        // A subscription made with a different server key can't receive our pushes: replace it.
        if (sub && sub.options && sub.options.applicationServerKey) {
          const current = new Uint8Array(sub.options.applicationServerKey);
          const wanted = keyBytes(publicKey);
          if (current.length !== wanted.length || current.some((b, i) => b !== wanted[i])) {
            await sub.unsubscribe();
            sub = null;
          }
        }
        if (!sub) {
          sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(publicKey) });
        }
        return JSON.stringify(sub.toJSON());
      } catch (e) {
        console.warn('Push subscription failed', e);
        return '';
      }
    },

    // This browser's current subscription JSON without asking anything, or '' if there is none.
    async current() {
      try {
        if (!supported() || Notification.permission !== 'granted') return '';
        const reg = await navigator.serviceWorker.getRegistration(SW_SCOPE);
        const sub = reg && await reg.pushManager.getSubscription();
        return sub ? JSON.stringify(sub.toJSON()) : '';
      } catch (_) {
        return '';
      }
    },

    // Stops pushes to this browser. Resolves to the JSON of the subscription it ended ('' if none).
    async unsubscribe() {
      try {
        if (!supported()) return '';
        const reg = await navigator.serviceWorker.getRegistration(SW_SCOPE);
        const sub = reg && await reg.pushManager.getSubscription();
        if (!sub) return '';
        const json = JSON.stringify(sub.toJSON());
        await sub.unsubscribe();
        return json;
      } catch (_) {
        return '';
      }
    },
  };
})();

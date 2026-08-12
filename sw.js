// NHIA Monitor PWA — Service Worker v66
const CACHE_NAME = 'nhia-v78';
const ASSETS = ['./index.html','./manifest.json'];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(ASSETS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(k => k !== CACHE_NAME).map(k => {
          console.log('[SW v66] Deleting old cache:', k);
          return caches.delete(k);
        })
      ))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.mode === 'navigate' ||
      (e.request.method === 'GET' && url.pathname.endsWith('.html'))) {
    e.respondWith(
      fetch(e.request.clone())
        .then(res => {
          if (res && res.status === 200) {
            caches.open(CACHE_NAME).then(c => c.put(e.request, res.clone()));
          }
          return res;
        })
        .catch(() => caches.match('./index.html'))
    );
  } else {
    e.respondWith(
      caches.match(e.request)
        .then(r => r || fetch(e.request))
        .catch(() => new Response('Offline', { status: 503 }))
    );
  }
});

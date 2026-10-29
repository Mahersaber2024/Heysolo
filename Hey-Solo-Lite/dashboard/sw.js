/* HeySolo dashboard service worker.
   Shows price alerts in the phone or desktop notification list, even when the site or the browser is closed.
   The Worker sends an encrypted Web Push with the full message; if a push arrives without data, this file reads /v1/alerts itself. */
var DBN = 'hs-push', ST = 'kv';
function idb() {
  return new Promise(function (res, rej) {
    var r = indexedDB.open(DBN, 1);
    r.onupgradeneeded = function () { r.result.createObjectStore(ST); };
    r.onsuccess = function () { res(r.result); };
    r.onerror = function () { rej(r.error); };
  });
}
function kvGet(k) {
  return idb().then(function (d) {
    return new Promise(function (res) {
      var q = d.transaction(ST).objectStore(ST).get(k);
      q.onsuccess = function () { res(q.result); };
      q.onerror = function () { res(undefined); };
    });
  }).catch(function () { return undefined; });
}
function kvSet(k, v) {
  return idb().then(function (d) {
    return new Promise(function (res) {
      var t = d.transaction(ST, 'readwrite');
      t.objectStore(ST).put(v, k);
      t.oncomplete = function () { res(); };
      t.onerror = function () { res(); };
    });
  }).catch(function () {});
}

self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) { e.waitUntil(self.clients.claim()); });

var TXT = {
  fa: { cross: 'قیمت از این سطح عبور کرد', alert: 'آلارت قیمت', up: 'قیمت از پایین به', down: 'قیمت از بالا به', hit: 'رسید', test: 'تست اعلان: همه‌چیز درست کار می‌کند',
        gen: 'آلارت جدید', open: 'باز کردن', dismiss: 'بستن', now: 'قیمت لحظه‌ای' },
  en: { cross: 'Price crossed this level', alert: 'Price alert', up: 'Price rose to', down: 'Price fell to', hit: '', test: 'Test notification: everything works',
        gen: 'New alert', open: 'Open', dismiss: 'Dismiss', now: 'Now' }
};

function setBadge(n) {
  try {
    if (self.navigator && self.navigator.setAppBadge) { return n > 0 ? self.navigator.setAppBadge(n) : self.navigator.clearAppBadge(); }
  } catch (e) {}
}

var AUTO_CLOSE_MS = 60000;   // every notification removes itself (also from the notification center) after 1 minute
var closers = [];
function scheduleClose(tag) {
  closers.push(new Promise(function (res) {
    setTimeout(function () {
      self.registration.getNotifications({ tag: tag }).then(function (l) { l.forEach(function (n) { n.close(); }); res(); }).catch(res);
    }, AUTO_CLOSE_MS);
  }));
}
function show(title, opts) {
  return self.registration.showNotification(title, opts).then(function () { scheduleClose(opts.tag); });
}

function baseOpts(L, tag, body, dir, renotify) {
  return {
    body: body, tag: tag, renotify: false, requireInteraction: false, silent: false,
    vibrate: dir === 'down' ? [400, 120, 400, 120, 400] : [150, 80, 150, 80, 300],
    icon: 'n-logo.png?v=1', badge: 'badge.png',
    data: { url: self.registration.scope }, timestamp: Date.now()
  };
}

function showFromData(d, L) {
  if (d.k === 'alert') {
    // minimal monochrome style: one-line title, one-line body, no action buttons
    var isTest = d.sym === 'TEST';
    var body = isTest ? L.test : (L.cross + ' · ' + L.now + ' ' + d.price);
    var title = isTest ? 'HeySolo' : (d.sym + '  ' + (d.dir === 'down' ? '↓' : '↑') + '  ' + d.level);
    return [show(title, baseOpts(L, 'hsn-' + d.id, body, d.dir, true))];
  }
  return [];
}

function onPush(event) {
  var data = null;
  try { data = event.data ? event.data.json() : null; } catch (e) { data = null; }
  return Promise.all([kvGet('cfg'), kvGet('lastId'), kvGet('badge'), self.clients.matchAll({ type: 'window', includeUncontrolled: true })]).then(function (r) {
    var cfg = r[0] || {}, lastId = +r[1] || 0, badge = +r[2] || 0, wins = r[3] || [];
    var L = TXT[cfg.lang === 'fa' ? 'fa' : 'en'];
    // the site is open and visible: it shows its own toast + sound, tell it to refresh now
    var visible = wins.some(function (c) { return c.visibilityState === 'visible'; });
    var MOBILE = /Android|iPhone|iPad|iPod|Mobile/i.test((self.navigator && self.navigator.userAgent) || '');
    // phones never show an in-page toast, so they always get the system notification
    if (visible && !MOBILE) { wins.forEach(function (c) { try { c.postMessage({ type: 'hs-poll' }); } catch (e) {} }); return; }
    var done = function (shows, maxId) {
      badge += shows.length;
      return Promise.all(shows).then(function () { setBadge(badge); return Promise.all([kvSet('badge', badge), maxId ? kvSet('lastId', maxId) : null]); });
    };
    if (data && data.k) {
      var shows = showFromData(data, L);
      if (!shows.length) shows.push(show('HeySolo', baseOpts(L, 'hsn-generic', L.gen, '', true)));   // a push must always show something
      return done(shows, data.k === 'alert' ? Math.max(lastId, +data.id || 0) : 0);
    }
    // empty push: read the alerts from the Worker
    var load = (cfg.url && cfg.key)
      ? fetch(cfg.url + '/v1/alerts?login=' + encodeURIComponent(cfg.login || ''), { headers: { 'X-HeySolo-Dashboard-Key': cfg.key }, cache: 'no-store' })
          .then(function (x) { return x.json(); }).then(function (d) { return (d && d.ok && d.alerts) || []; }).catch(function () { return []; })
      : Promise.resolve([]);
    return load.then(function (list) {
      var now = Date.now() / 1000;
      var fresh = list.filter(function (a) { return +a.id > lastId && (now - (+a.t || 0)) < 900; });
      var maxId = list.reduce(function (m, a) { return Math.max(m, +a.id || 0); }, lastId);
      var shows = [];
      fresh.slice(-3).forEach(function (a) { shows = shows.concat(showFromData({ k: 'alert', id: a.id, sym: a.sym, dir: a.dir, level: a.level, price: a.price }, L)); });
      if (!shows.length) shows.push(show('HeySolo', baseOpts(L, 'hsn-generic', L.gen, '', true)));   // a push must always show something
      return done(shows, maxId);
    });
  });
}
self.addEventListener('push', function (e) {
  // keep the worker alive until the auto-close timers have run
  e.waitUntil(onPush(e).then(function () { return Promise.all(closers.splice(0)); }));
});

self.addEventListener('notificationclick', function (e) {
  e.notification.close();
  if (e.action === 'dismiss') return;
  var url = (e.notification.data && e.notification.data.url) || self.registration.scope;
  e.waitUntil(Promise.all([kvSet('badge', 0), setBadge(0)]).then(function () {
    return self.clients.matchAll({ type: 'window', includeUncontrolled: true });
  }).then(function (wins) {
    for (var i = 0; i < wins.length; i++) { if ('focus' in wins[i]) return wins[i].focus(); }
    return self.clients.openWindow(url);
  }));
});

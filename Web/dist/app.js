'use strict';
let library, mode = 'All', page = 0, player = null, activeKey = null, timer = null;
let mutations = Promise.resolve();
const $ = selector => document.querySelector(selector);
const tabs = ['All', 'Sleep', 'Eat', 'Other', 'Favourites', 'Deleted'];
function video(story) {
  try {
    const u = new URL(story.storyURL), parts = u.pathname.split('/').filter(Boolean);
    let id;
    if (u.hostname === 'youtu.be') id = parts[0];
    else if (u.hostname === 'youtube.com' || u.hostname.endsWith('.youtube.com') || u.hostname === 'www.youtube-nocookie.com') {
      if (parts[0] === 'watch') id = u.searchParams.get('v');
      else if (parts.length === 2 && ['shorts', 'embed', 'live'].includes(parts[0])) id = parts[1];
    }
    if (id && /^[\w-]{11}$/.test(id)) {
      const raw = u.searchParams.get('t') || u.searchParams.get('start') || '0';
      const start = /^\d+$/.test(raw) ? Number(raw) : [...raw.matchAll(/(\d+)([hms])/g)].reduce((n, m) => n + Number(m[1]) * ({h:3600,m:60,s:1}[m[2]]), 0);
      return {kind:'youtube', id, key:`youtube:${id}`, start};
    }
    if (['instagram.com', 'www.instagram.com', 'm.instagram.com'].includes(u.hostname) && parts.length === 2 && ['p','reel','reels','tv'].includes(parts[0]) && /^[\w-]+$/.test(parts[1]))
      return {kind:'instagram', id:parts[1], key:`instagram:${parts[1]}`, path:`${parts[0] === 'reels' ? 'reel' : parts[0]}/${parts[1]}`};
  } catch {}
  return null;
}
function safeURL(raw) { try { const u = new URL(raw); return ['http:', 'https:'].includes(u.protocol) ? u.href : '#'; } catch { return '#'; } }
async function request(path, action) {
  const response = await fetch(path, action ? {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(action), keepalive:true} : {});
  const data = await response.json();
  if (!response.ok) throw Error(data.error || 'Request failed');
  return data;
}
function change(action, redraw = true) {
  mutations = mutations.then(async () => {
    library = await request('/api/change', action);
    if (redraw) render();
  }).catch(error => { $('#status').textContent = `Couldn't save: ${error.message}`; });
  return mutations;
}
function saveProgress(ended = false) {
  if (player && activeKey && typeof player.getCurrentTime === 'function') {
    const seconds = ended ? 0 : player.getCurrentTime();
    if (Number.isFinite(seconds)) change({kind:'progress', key:activeKey, seconds}, false);
  }
}
function stop() {
  clearInterval(timer); timer = null;
  saveProgress();
  if (player) { player.destroy(); player = null; }
  activeKey = null;
}
let apiPromise;
function youtubeAPI() {
  if (!apiPromise) apiPromise = new Promise((resolve, reject) => {
    if (window.YT?.Player) return resolve();
    window.onYouTubeIframeAPIReady = resolve;
    const script = document.createElement('script'); script.src = 'https://www.youtube.com/iframe_api';
    script.onerror = () => { apiPromise = null; reject(Error('YouTube could not load. Use the open-original link.')); };
    document.head.append(script);
  });
  return apiPromise;
}
let playRequest = 0;
async function play(story, media) {
  stop();
  // Rebuild thumbnails to remove any previous Instagram iframe.
  document.querySelectorAll('.media').forEach(node => { if (node !== media && node._story) thumbnail(node._story, node); });
  const token = ++playRequest, v = video(story);
  if (!v) { window.open(safeURL(story.storyURL), '_blank', 'noopener'); return; }
  media.replaceChildren();
  if (v.kind === 'instagram') {
    const iframe = document.createElement('iframe'); iframe.src = `https://www.instagram.com/${v.path}/embed/`;
    iframe.title = story.title; iframe.allowFullscreen = true; media.append(iframe); return;
  }
  media.textContent = 'Loading YouTube…';
  try {
    await youtubeAPI();
    if (token !== playRequest || !media.isConnected) return;
    const host = document.createElement('div'); media.replaceChildren(host); activeKey = v.key;
    player = new YT.Player(host, {videoId:v.id, width:'100%', height:'100%', playerVars:{origin:location.origin, playsinline:1, start:Math.floor(library.progress[v.key] ?? v.start)}, events:{
      onReady: event => { event.target.playVideo(); timer = setInterval(() => saveProgress(), 5000); },
      onStateChange: event => { if (event.data === 1) { activeKey = v.key; clearInterval(timer); timer = setInterval(() => saveProgress(), 5000); } if (event.data === 0) { clearInterval(timer); saveProgress(true); activeKey = null; } else if (event.data === 2) saveProgress(); },
      onError: event => { $('#status').textContent = `YouTube couldn't play this video here (error ${event.data}). Use ↗ beside its title to watch on YouTube.`; }
    }});
  } catch (error) { media.textContent = error.message; }
}
function button(text, action) { const node = document.createElement('button'); node.textContent = text; node.onclick = action; return node; }
function thumbnail(story, media) {
  const v = video(story); media.replaceChildren(); media._story = story;
  if (!v || mode === 'Deleted') return;
  const trigger = button('', () => play(story, media)); trigger.setAttribute('aria-label', `Play ${story.title}`);
  if (v.kind === 'youtube') { const img = document.createElement('img'); img.src = `https://i.ytimg.com/vi/${v.id}/hqdefault.jpg`; img.alt = ''; img.loading = 'lazy'; trigger.append(img); }
  const icon = document.createElement('span'); icon.className = 'play'; icon.textContent = '▶'; trigger.append(icon); media.append(trigger);
}
function render() {
  stop(); ++playRequest;
  $('nav').replaceChildren(...tabs.map(tab => { const node = button(tab, () => { mode = tab; page = 0; render(); }); if (tab === mode) node.setAttribute('aria-current', 'page'); return node; }));
  const query = $('#search').value.toLowerCase();
  const source = mode === 'Favourites' ? Object.values(library.favourites).sort((a,b) => b.savedAt-a.savedAt).map(entry => entry.story) : library.bookmarks;
  const stories = source.filter(story => {
    const v = video(story), key = v?.key || story.storyURL, removed = library.removedKeys.includes(key);
    if (!story.title.toLowerCase().includes(query)) return false;
    if (mode === 'Favourites') return true;
    if (mode === 'Deleted') return removed;
    if (removed) return false;
    if (mode === 'Other') return !v;
    if (mode === 'All') return !!v;
    return !!v && (library.sectionKeys[mode.toLowerCase()] || []).includes(key);
  });
  page = Math.max(0, Math.min(page, Math.ceil(stories.length / 15) - 1));
  $('#status').textContent = `${stories.length} ${stories.length === 1 ? 'bookmark' : 'bookmarks'} · ${mode}`;
  $('#feed').replaceChildren();
  for (const story of stories.slice(page*15, page*15+15)) {
    const card = $('#card').content.firstElementChild.cloneNode(true), v = video(story), key = v?.key || story.storyURL;
    const media = card.querySelector('.media'); thumbnail(story, media);
    const title = card.querySelector('.title'); title.textContent = story.title; title.onclick = () => play(story, media);
    card.querySelector('.original').href = safeURL(story.storyURL);
    const actions = card.querySelector('.actions');
    actions.append(button(library.favourites[key] ? '★ Saved' : '☆ Favourite', () => change({kind:'favourite', key, id:story.id})));
    if (v && mode !== 'Deleted') for (const section of ['sleep','eat']) {
      const included = (library.sectionKeys[section] || []).includes(key);
      const name = section === 'sleep' ? 'Sleep' : 'Eat';
      const toggle = button('', () => change({kind:section, key, enabled:!included}));
      toggle.className = 'section-toggle';
      toggle.setAttribute('aria-label', `${name} for: ${story.title}`);
      toggle.setAttribute('aria-pressed', String(included));
      toggle.title = included ? `Remove from ${name}` : `Add to ${name}. Videos stay in All.`;
      const icon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      icon.setAttribute('viewBox', '0 0 24 24'); icon.setAttribute('aria-hidden', 'true');
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('d', section === 'sleep'
        ? 'M20.5 14.5A9 9 0 0 1 9.5 3.5a9 9 0 1 0 11 11Z'
        : 'M5 3v6m3-6v6m3-6v6M5 7h6M8 9v12M19 3c-3 3-4 7-4 10h4m0-10v18');
      icon.append(path); toggle.append(icon); actions.append(toggle);
    }
    const removed = library.removedKeys.includes(key);
    actions.append(button(removed ? 'Restore' : 'Remove', () => change({kind:'removed', key, enabled:!removed})));
    $('#feed').append(card);
  }
  if (!stories.length) { const empty = document.createElement('p'); empty.className = 'empty'; empty.textContent = query ? 'No matching bookmarks.' : 'No bookmarks here. Refresh Firefox to import your tv folder.'; $('#feed').append(empty); }
  const previous = button('Previous', () => { page--; render(); window.scrollTo(0,0); }), next = button('Next', () => { page++; render(); window.scrollTo(0,0); });
  previous.disabled = page === 0; next.disabled = (page+1)*15 >= stories.length;
  $('#pagination').replaceChildren(previous, document.createTextNode(`Page ${page+1} of ${Math.max(1,Math.ceil(stories.length/15))}`), next);
}
$('#search').oninput = () => { page = 0; render(); };
$('#refresh').onclick = async () => {
  $('#refresh').disabled = true; $('#status').textContent = 'Reading Firefox bookmarks…';
  try { stop(); await mutations; library = await request('/api/refresh', {}); render(); }
  catch (error) { $('#status').textContent = error.message; }
  finally { $('#refresh').disabled = false; }
};
window.addEventListener('pagehide', () => saveProgress());
document.addEventListener('visibilitychange', () => { if (document.hidden) saveProgress(); });
request('/api/library').then(data => { library = data; render(); }).catch(error => { $('#status').textContent = `Couldn't load the library: ${error.message}`; });

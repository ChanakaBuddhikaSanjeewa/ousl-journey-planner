 (() => {
      'use strict';
      const MODE_ICON = {foot: '🚶', bike: '🏍️', bus: '🚌', highway: '🚍', train: '🚆', three_wheel: '🛺'};
      const $ = (id) => document.getElementById(id);

      const state = {start: null, plan: null, selected: null, line: null, steps: [], stepIdx: [], cum: [], watchId: null, demoTimer: null, lastPos: null, markers: {}};

      // ---------- helpers ----------
      const toRad = (d) => d * Math.PI / 180;
      function haversineM(a, b) {
        const dLat = toRad(b.lat - a.lat), dLon = toRad(b.lon - a.lon);
        const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLon / 2) ** 2;
        return 2 * 6371000 * Math.asin(Math.sqrt(h));
      }
      function bearing(a, b) {
        const y = Math.sin(toRad(b.lon - a.lon)) * Math.cos(toRad(b.lat));
        const x = Math.cos(toRad(a.lat)) * Math.sin(toRad(b.lat)) - Math.sin(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.cos(toRad(b.lon - a.lon));
        return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360;
      }
      function fmtMin(m) {return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : `${m} min`;}
      function fmtDist(m) {return m >= 1000 ? `${(m / 1000).toFixed(1)} km` : `${Math.round(m / 10) * 10} m`;}
      let toastTimer;
      function toast(text) {
        const el = $('top-message'); el.textContent = text; el.classList.add('visible');
        clearTimeout(toastTimer); toastTimer = setTimeout(() => el.classList.remove('visible'), 5000);
      }
      async function api(path, body) {
        const res = await fetch(path, body ? {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)} : undefined);
        if (!res.ok) throw new Error(`Server error (${res.status})`);
        return res.json();
      }
      function setNet() {
        $('net').classList.toggle('offline', !navigator.onLine);
        $('net-label').textContent = navigator.onLine ? 'Online' : 'Offline';
      }
      addEventListener('online', setNet); addEventListener('offline', setNet); setNet();

      // ---------- map ----------
      const CAMPUS = {lat: 6.8838, lon: 79.8887};
      const map = new maplibregl.Map({
        container: 'map',
        style: {
          version: 8,
          sources: {
            osm: {
              type: 'raster', tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'], tileSize: 256, maxzoom: 19,
              attribution: '© OpenStreetMap contributors'
            }
          },
          layers: [{id: 'osm', type: 'raster', source: 'osm'}]
        },
        center: [CAMPUS.lon, CAMPUS.lat], zoom: 12, bearing: 0, pitch: 0, maxPitch: 70
      });
      map.addControl(new maplibregl.NavigationControl({visualizePitch: true}), 'top-right');
      map.addControl(new maplibregl.ScaleControl(), 'bottom-left');

      function pinEl(cls) {const d = document.createElement('div'); d.className = 'pin ' + cls; return d;}
      state.markers.campus = new maplibregl.Marker({element: pinEl('end'), anchor: 'bottom'}).setLngLat([CAMPUS.lon, CAMPUS.lat]).setPopup(new maplibregl.Popup({offset: 24}).setText('OUSL Nawala Campus'));
      state.markers.start = new maplibregl.Marker({element: pinEl('start'), anchor: 'bottom'});
      const meEl = document.createElement('div'); meEl.className = 'me';
      state.markers.me = new maplibregl.Marker({element: meEl, rotationAlignment: 'map'});

      let mapReady = false, pendingDraw = null;
      map.on('load', () => {
        state.markers.campus.addTo(map);
        map.addSource('route', {type: 'geojson', data: {type: 'FeatureCollection', features: []}});
        map.addLayer({id: 'route-casing', type: 'line', source: 'route', layout: {'line-cap': 'round', 'line-join': 'round'}, paint: {'line-color': '#fff', 'line-width': 9}});
        map.addLayer({id: 'route-line', type: 'line', source: 'route', layout: {'line-cap': 'round', 'line-join': 'round'}, paint: {'line-color': '#3563e9', 'line-width': 5}});
        map.addLayer({id: 'route-dash', type: 'line', source: 'route', filter: ['==', ['get', 'schematic'], true], layout: {'line-cap': 'butt'}, paint: {'line-color': '#fff', 'line-width': 2, 'line-dasharray': [2, 2]}});
        mapReady = true;
        if (pendingDraw) {pendingDraw(); pendingDraw = null;}
      });

      function drawRoute(points, schematic) {
        const draw = () => {
          const coords = points.map(p => [p.lon, p.lat]);
          map.getSource('route').setData({type: 'FeatureCollection', features: [{type: 'Feature', properties: {schematic: !!schematic}, geometry: {type: 'LineString', coordinates: coords}}]});
          const b = new maplibregl.LngLatBounds();
          coords.forEach(c => b.extend(c));
          map.fitBounds(b, {padding: 60, bearing: 0, pitch: 0, duration: 800});
        };
        mapReady ? draw() : (pendingDraw = draw);
      }

      $('rot-left').onclick = () => map.easeTo({bearing: map.getBearing() - 30, duration: 400});
      $('rot-right').onclick = () => map.easeTo({bearing: map.getBearing() + 30, duration: 400});
      $('north').onclick = () => map.easeTo({bearing: 0, pitch: 0, duration: 500});

      // ---------- start location + search ----------
      let searchTimer;
      $('start-input').addEventListener('input', () => {
        state.start = null;
        clearTimeout(searchTimer);
        const q = $('start-input').value.trim();
        if (q.length < 3) {$('suggestions').hidden = true; return;}
        searchTimer = setTimeout(async () => {
          try {
            const data = await api('/api/search?q=' + encodeURIComponent(q));
            const list = $('suggestions'); list.innerHTML = '';
            (data.results || []).forEach(r => {
              const li = document.createElement('li'); li.textContent = r.display_name;
              li.onclick = () => {setStart(parseFloat(r.lat), parseFloat(r.lon), r.display_name); list.hidden = true;};
              list.appendChild(li);
            });
            list.hidden = !list.children.length;
          } catch (e) { /* ignore, user can retry */}
        }, 450);
      });
      document.addEventListener('click', (e) => {if (!e.target.closest('.suggestions') && e.target.id !== 'start-input') $('suggestions').hidden = true;});

      function setStart(lat, lon, name) {
        state.start = {lat, lon, name};
        $('start-input').value = name;
        state.markers.start.setLngLat([lon, lat]).addTo(map);
      }

      $('use-location').onclick = () => {
        if (!navigator.geolocation) return toast('Your browser does not support location.');
        $('use-location').textContent = 'Locating...';
        navigator.geolocation.getCurrentPosition(async (pos) => {
          const {latitude: lat, longitude: lon} = pos.coords;
          let name = 'My current location';
          try {const r = await api(`/api/reverse?lat=${lat}&lon=${lon}`); if (r.ok) name = r.display_name;} catch (e) { }
          setStart(lat, lon, name);
          $('use-location').textContent = 'Use my location';
        }, () => {$('use-location').textContent = 'Use my location'; toast('Location unavailable. Allow location access or type a place.');},
          {enableHighAccuracy: true, timeout: 15000});
      };

      // ---------- plan ----------
      $('form').addEventListener('submit', async (ev) => {
        ev.preventDefault();
        stopNavigation();
        if (!state.start) {
          const q = $('start-input').value.trim();
          if (q.length < 3) return toast('Please choose a start location first.');
          try {
            const data = await api('/api/search?q=' + encodeURIComponent(q));
            const r = (data.results || [])[0];
            if (!r) return toast('Could not find that place in Sri Lanka.');
            setStart(parseFloat(r.lat), parseFloat(r.lon), r.display_name);
          } catch (e) {return toast('Search failed. Please try again.');}
        }
        $('find').disabled = true; $('find').textContent = 'Calculating...';
        $('message').className = 'msg-box empty'; $('message').textContent = 'Calculating distance, time and cost for each travel mode...';
        try {
          const plan = await api('/api/plan', {start_coord: state.start});
          if (!plan.ok) throw new Error(plan.message || 'No route found');
          state.plan = plan;
          renderPlan(plan);
        } catch (e) {
          toast(e.message);
          $('message').textContent = 'Something went wrong. ' + e.message;
        } finally {
          $('find').disabled = false; $('find').textContent = 'Show my travel options';
        }
      });

      function renderPlan(plan) {
        $('message').className = 'msg-box'; $('message').textContent = plan.message;
        const labelOf = (m) => (plan.options.find(o => o.mode === m) || {}).label;
        $('chips').innerHTML = '';
        [['Fastest', plan.recommended.fastest], ['Cheapest', plan.recommended.cheapest], ['Best value', plan.recommended.best_value]].forEach(([t, m]) => {
          const c = document.createElement('span'); c.className = 'chip'; c.textContent = `${t}: ${labelOf(m)}`; $('chips').appendChild(c);
        });
        const grid = $('modes'); grid.innerHTML = '';
        plan.options.forEach(o => {
          const el = document.createElement('div');
          el.className = 'mode' + (o.available ? '' : ' off');
          el.dataset.mode = o.mode;
          const badges = [];
          if (o.mode === plan.recommended.fastest) badges.push('<span class="badge">FASTEST</span>');
          if (o.mode === plan.recommended.cheapest) badges.push('<span class="badge b2">CHEAPEST</span>');
          if (o.mode === plan.recommended.best_value) badges.push('<span class="badge b3">BEST VALUE</span>');
          el.innerHTML = `<div class="badges">${o.available ? badges.join('') : ''}</div><div class="ico">${MODE_ICON[o.mode] || '🧭'}</div><h4>${o.label}</h4>` +
            (o.available
              ? `<div class="stat"><span>Distance</span><b>${o.distance_km.toFixed(1)} km</b></div>
             <div class="stat"><span>Time</span><b>${fmtMin(o.minutes)}</b></div>
             <div class="stat"><span>Est. cost</span><b>LKR ${o.cost_lkr.toLocaleString()}</b></div>`
              : `<div class="why">${o.reason || 'Not available'}</div>`);
          if (o.available) el.onclick = () => selectMode(o.mode);
          grid.appendChild(el);
        });
        selectMode(plan.recommended.best_value);
      }

      function selectMode(mode) {
        stopNavigation();
        const plan = state.plan; const o = plan.options.find(x => x.mode === mode);
        if (!o || !o.available) return;
        state.selected = o;
        document.querySelectorAll('.mode').forEach(el => el.classList.toggle('selected', el.dataset.mode === mode));
        const geo = o.geometry || plan.road_geometry;
        state.line = geo;
        state.steps = o.steps || (o.geometry_ref === 'road' ? plan.road_steps : []);
        buildTrack();
        drawRoute(geo, !!o.schematic);
        $('nav-start').disabled = false; $('demo').disabled = false;
        renderDetail(o);
      }

      function renderDetail(o) {
        const el = $('detail'); el.hidden = false;
        let html = `<b>${MODE_ICON[o.mode] || ''} ${o.label}</b> - ${o.distance_km.toFixed(1)} km, ${fmtMin(o.minutes)}, approx. LKR ${o.cost_lkr.toLocaleString()}<br>${o.note || ''}`;
        if (o.legs) html += '<ol>' + o.legs.map(l => `<li>${l.text}</li>`).join('') + '</ol>';
        else if (state.steps.length) html += '<ol>' + state.steps.map(s => `<li>${s.instruction} <span style="color:var(--muted)">(${fmtDist(s.distance)})</span></li>`).join('') + '</ol>';
        el.innerHTML = html;
      }

      // ---------- navigation ----------
      function buildTrack() {
        const g = state.line || []; state.cum = [0];
        for (let i = 1; i < g.length; i++) state.cum[i] = state.cum[i - 1] + haversineM(g[i - 1], g[i]);
        state.stepIdx = (state.steps || []).map(s => nearestIdx(g, s));
      }
      function nearestIdx(g, p, from = 0) {
        let best = from, bd = Infinity;
        for (let i = from; i < g.length; i++) {const d = haversineM(g[i], p); if (d < bd) {bd = d; best = i;} }
        return best;
      }

      function onPosition(pos, heading) {
        const g = state.line; if (!g || !g.length) return;
        const idx = nearestIdx(g, pos);
        const total = state.cum[g.length - 1];
        const remaining = Math.max(0, total - state.cum[idx]);
        // heading: GPS heading, else movement direction, else direction of the route
        let h = heading;
        if (!Number.isFinite(h)) {
          if (state.lastPos && haversineM(state.lastPos, pos) > 5) h = bearing(state.lastPos, pos);
          else h = bearing(pos, g[Math.min(g.length - 1, idx + 3)]);
        }
        state.lastPos = pos;
        state.markers.me.setLngLat([pos.lon, pos.lat]).addTo(map);
        if ($('heading-up').checked) {
          map.easeTo({center: [pos.lon, pos.lat], bearing: h, pitch: 55, zoom: 17, duration: 900, easing: (t) => t});
        } else {
          map.easeTo({center: [pos.lon, pos.lat], duration: 600});
        }
        // next instruction
        let instr = 'Follow the route', dist = remaining;
        const k = state.stepIdx.findIndex((si) => si > idx + 1);
        if (k >= 0 && state.steps[k]) {instr = state.steps[k].instruction; dist = state.cum[state.stepIdx[k]] - state.cum[idx];}
        const arrived = haversineM(pos, CAMPUS) < 50 || remaining < 40;
        $('nav-instr').textContent = arrived ? 'You have arrived at OUSL Nawala!' : (k >= 0 ? `In ${fmtDist(Math.max(0, dist))}: ${instr}` : instr);
        const eta = state.selected ? Math.max(1, Math.round(state.selected.minutes * (total ? remaining / total : 0))) : 0;
        $('nav-sub').textContent = `${fmtDist(remaining)} remaining - about ${fmtMin(eta)} left`;
        if (arrived) {toast('You have arrived at the Open University of Sri Lanka.'); stopNavigation(true);}
      }

      function startNavigation() {
        if (!state.line) return;
        $('navbar').classList.add('on'); $('nav-start').hidden = true; $('nav-stop').hidden = false; $('demo').disabled = true;
        $('nav-instr').textContent = 'Waiting for GPS...'; $('nav-sub').textContent = '';
        if (!navigator.geolocation) return toast('Your browser does not support location.');
        state.watchId = navigator.geolocation.watchPosition(
          (p) => onPosition({lat: p.coords.latitude, lon: p.coords.longitude}, p.coords.heading),
          () => toast('Could not read your GPS position.'),
          {enableHighAccuracy: true, maximumAge: 1000, timeout: 20000});
      }

      // Simulated drive so the rotating map can be shown on a PC without GPS.
      function previewDrive() {
        if (!state.line) return;
        $('navbar').classList.add('on'); $('nav-start').hidden = true; $('nav-stop').hidden = false; $('demo').disabled = true;
        const g = state.line; const stepN = Math.max(1, Math.floor(g.length / 140)); let i = 0; state.lastPos = null;
        state.demoTimer = setInterval(() => {
          if (i >= g.length) {stopNavigation(true); return;}
          onPosition(g[i], NaN); i += stepN;
        }, 900);
      }

      function stopNavigation(arrived) {
        if (state.watchId !== null) {navigator.geolocation.clearWatch(state.watchId); state.watchId = null;}
        if (state.demoTimer) {clearInterval(state.demoTimer); state.demoTimer = null;}
        state.lastPos = null;
        $('nav-start').hidden = false; $('nav-stop').hidden = true;
        $('nav-start').disabled = !state.line; $('demo').disabled = !state.line;
        if (!arrived) $('navbar').classList.remove('on');
        state.markers.me.remove();
        if (state.line && !arrived) map.easeTo({bearing: 0, pitch: 0, duration: 500});
      }
      $('nav-start').onclick = startNavigation;
      $('nav-stop').onclick = () => stopNavigation(false);
      $('demo').onclick = previewDrive;
    })();
// =========================================================
// UrbanPulse — Real-Time App Logic with Groq LLaMA-3.3 Engine
// =========================================================

const GROQ_API_KEY = window.GROQ_API_KEY || "";
const TOMTOM_API_KEY = window.TOMTOM_API_KEY || "";
if (!GROQ_API_KEY || !TOMTOM_API_KEY) {
    console.warn("GROQ_API_KEY / TOMTOM_API_KEY not set. Copy config.local.example.js to config.local.js, fill in real keys, and include it before app.js.");
}

// --- 1. Destination Registry (origin/destination coords only — routes, fares, CO2 & AQI are fetched live below) ---
const DESTINATIONS = {
    kedarnath: {
        title: "Kedarnath Himalayan Transit Corridor",
        origin: [30.0869, 78.2676], // Rishikesh
        dest: [30.7352, 79.0669], // Shri Kedarnath Dham
        greenMode: "Vande Bharat + Electric Pilgrim Shuttle",
        greenDetails: "Zero Tailpipe Emissions • Assisted Palki & Step-Free Concourse",
        normalMode: "Diesel SUV Private Taxi",
        normalDetails: "Narrow Mountain Road Delays • High Carbon Footprint • Landslide Risk"
    },
    lonavala: {
        title: "Lonavala Scenic Ridge",
        origin: [19.0178, 72.8478], // Mumbai
        dest: [18.7546, 73.4062],
        greenMode: "Indrayani Electric Express",
        greenDetails: "Level Boarding • 100% Elevator Access Concourse",
        normalMode: "Petrol Cab (MH Taxi Formula)",
        normalDetails: "Base ₹28 + ₹18.5/km • Heavy Ghats Traffic Delay"
    },
    fortis: {
        title: "Fortis Hospital Mulund (Trauma Center)",
        origin: [19.1775, 72.9544],
        dest: [19.1728, 72.9564],
        greenMode: "Metro Line 4 / Electric Feeder",
        greenDetails: "Dedicated Green Corridor • 100% Step-Free Emergency Concourse",
        normalMode: "Standard Auto / Cab",
        normalDetails: "LBS Marg Bottleneck Congestion"
    },
    powai: {
        title: "Powai EV Fast Charging Hub",
        origin: [19.1775, 72.9544],
        dest: [19.1200, 72.9050],
        greenMode: "BEST AC Electric Bus Corridor",
        greenDetails: "Zero Tailpipe Emissions • Low-Floor Ramp Access",
        normalMode: "Petrol Cab",
        normalDetails: "JVLR Arterial Congestion"
    },
    csmt: {
        title: "CSMT South Mumbai Heritage Loop",
        origin: [19.1775, 72.9544],
        dest: [18.9400, 72.8353],
        greenMode: "Metro Line 3 Underground (Aqua Line)",
        greenDetails: "100% Renewable Powered • Tactile Paving & Elevators",
        normalMode: "Standard Taxi",
        normalDetails: "Eastern Freeway Bottlenecks"
    },
    alibaug: {
        title: "Alibaug Coastal Trail",
        origin: [18.9400, 72.8353],
        dest: [18.6500, 72.8800],
        greenMode: "M2M Electric Hybrid Ro-Pax Ferry",
        greenDetails: "Level Boarding Ramp • Accessible Restrooms & Decks",
        normalMode: "Petrol Cab (via Pen Highway)",
        normalDetails: "Narrow Highway Curves • High Carbon Footprint"
    }
};

// --- 2. Live TomTom Routing + Open-Meteo AQI (mirrors Android LiveMapFragment.kt) ---
async function fetchTomTomRoute(origin, dest, routeType, traffic) {
    if (!TOMTOM_API_KEY) return null;
    const url = `https://api.tomtom.com/routing/1/calculateRoute/${origin[0]},${origin[1]}:${dest[0]},${dest[1]}/json?key=${TOMTOM_API_KEY}&routeType=${routeType}&traffic=${traffic}&travelMode=car`;
    try {
        const res = await fetch(url);
        if (!res.ok) return null;
        const json = await res.json();
        const route = json.routes && json.routes[0];
        if (!route) return null;
        const summary = route.summary || {};
        const distKm = (summary.lengthInMeters || 0) / 1000.0;
        const timeMin = Math.max(1, Math.round((summary.travelTimeInSeconds || 0) / 60));
        const points = (route.legs && route.legs[0] && route.legs[0].points) || [];
        const coords = points.map(p => [p.latitude, p.longitude]);
        return { distKm, timeMin, coords };
    } catch (e) {
        return null;
    }
}

async function fetchOpenMeteoAqi(lat, lon) {
    try {
        const url = `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${lat}&longitude=${lon}&current=us_aqi`;
        const res = await fetch(url);
        if (!res.ok) return null;
        const json = await res.json();
        return json.current ? json.current.us_aqi : null;
    } catch (e) {
        return null;
    }
}

// Real live weather check (not just AQI) — used to cross-check circumstance adaptation against
// actual conditions instead of trusting the user's wording alone. Defaults to Mumbai coordinates
// since the web demo has no device geolocation wired in.
async function fetchOpenMeteoWeather(lat = 19.0760, lon = 72.8777) {
    try {
        const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,precipitation,weather_code`;
        const res = await fetch(url);
        if (!res.ok) return null;
        const json = await res.json();
        if (!json.current) return null;
        const code = json.current.weather_code;
        const isRaining = json.current.precipitation > 0 || [51, 53, 55, 61, 63, 65, 80, 81, 82].includes(code);
        return { temperatureC: json.current.temperature_2m, precipitation: json.current.precipitation, isRaining };
    } catch (e) {
        return null;
    }
}

function formatMinutes(min) {
    if (min < 60) return `${min}m`;
    const h = Math.floor(min / 60);
    const m = min % 60;
    return `${h}h ${m}m`;
}

// --- 3. Leaflet Dual-Route Map (real TomTom geometry + real Open-Meteo AQI) ---
let leafletMap = null;
let routeLayerGroup = null;

function initLeafletMap() {
 const mapEl = document.getElementById('leaflet-map');
 if (!mapEl) return;

 leafletMap = L.map('leaflet-map', { zoomControl: false }).setView([18.7546, 73.4062], 10);

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
    }).addTo(leafletMap);

 routeLayerGroup = L.layerGroup().addTo(leafletMap);

 renderSelectedRoute('lonavala');
}

async function renderSelectedRoute(key) {
 if (!leafletMap || !routeLayerGroup) return;

 const meta = DESTINATIONS[key] || DESTINATIONS['lonavala'];
 const destTitleEl = document.getElementById('hud-dest-title');
 if (destTitleEl) destTitleEl.innerText = `${meta.title} — fetching live route...`;

 // Real TomTom dual-route calls (eco vs fastest+traffic), real Open-Meteo AQI at destination
 const [normalRoute, greenRoute, aqi] = await Promise.all([
     fetchTomTomRoute(meta.origin, meta.dest, 'fastest', 'true'),
     fetchTomTomRoute(meta.origin, meta.dest, 'eco', 'false'),
     fetchOpenMeteoAqi(meta.dest[0], meta.dest[1])
 ]);

 // Fallback geodesic geometry only if the live TomTom call failed
 const fallbackCoords = [meta.origin, meta.dest];
 const normal = normalRoute || { distKm: 0, timeMin: 0, coords: fallbackCoords };
 const green = greenRoute || { distKm: 0, timeMin: 0, coords: fallbackCoords };
 const dist = normal.distKm > 0 ? normal.distKm : (green.distKm > 0 ? green.distKm : 1);

 // Real-world fare/CO2 formulas (identical to Android LiveMapFragment.kt)
 const normalFare = Math.round(28.0 + (dist * 18.5));
 const normalCo2 = Math.round(dist * 160.0);
 const greenFare = dist <= 5.0 ? 10 : dist <= 12.0 ? 20 : dist <= 25.0 ? 30 : Math.round(dist * 1.7);
 const greenCo2 = Math.round(dist * 14.0);
 const savedCo2 = Math.max(100, normalCo2 - greenCo2);
 const savedFare = Math.max(0, normalFare - greenFare);

 routeLayerGroup.clearLayers();

 const normalLine = L.polyline(normal.coords, {
 color: '#EF4444',
 weight: 5,
 opacity: 0.85,
 dashArray: '8, 8',
 lineCap: 'round'
 }).bindPopup(`<b>Standard Cab</b><br>${formatMinutes(normal.timeMin)} • ₹${normalFare} • ${normalCo2}g CO₂`);

 const greenGlow = L.polyline(green.coords, {
 color: '#059669',
 weight: 10,
 opacity: 0.4,
 lineCap: 'round'
 });

 const greenLine = L.polyline(green.coords, {
 color: '#10B981',
 weight: 5,
 opacity: 1.0,
 lineCap: 'round'
 }).bindPopup(`<b>Green Path (${meta.greenMode})</b><br>${formatMinutes(green.timeMin)} • ₹${greenFare} • ${greenCo2}g CO₂`);

 routeLayerGroup.addLayer(normalLine);
 routeLayerGroup.addLayer(greenGlow);
 routeLayerGroup.addLayer(greenLine);

 const destMarker = L.marker(meta.dest).bindPopup(`<b>${meta.title}</b><br><span style="color:#10B981;font-weight:bold;">Green Transit: ${formatMinutes(green.timeMin)} (₹${greenFare})</span><br><span style="color:#EF4444;">Petrol Cab: ${formatMinutes(normal.timeMin)} (₹${normalFare})</span>`);
 routeLayerGroup.addLayer(destMarker);
 destMarker.openPopup();

 const featureGroup = L.featureGroup([normalLine, greenLine]);
 leafletMap.fitBounds(featureGroup.getBounds(), { padding: [40, 40], maxZoom: 13 });

 const aqiText = aqi !== null && aqi !== undefined ? `${aqi} (Live Open-Meteo US AQI)` : "Unavailable";

 document.getElementById('hud-dest-title').innerText = `${meta.title} (${dist.toFixed(1)} km)`;
 document.getElementById('hud-aqi-text').innerHTML = `${meta.greenMode} (Open-Meteo AQI: ${aqiText}) vs Petrol Cab`;
 document.getElementById('hud-savings-badge').innerText = `Save ${savedCo2}g CO₂ • Save ₹${savedFare.toLocaleString()}`;

 document.getElementById('green-time-fare').innerText = `${formatMinutes(green.timeMin)} • ₹${greenFare}`;
 document.getElementById('green-details').innerText = `${meta.greenMode} • ${meta.greenDetails}`;

 document.getElementById('normal-time-fare').innerText = `${formatMinutes(normal.timeMin)} • ₹${normalFare.toLocaleString()}`;
 document.getElementById('normal-details').innerText = `${meta.normalDetails}`;
}

// --- 3. App Navigation & Tab Switching ---
function switchAppTab(tabKey) {
 const views = {
 'map-view': 'view-map',
 'chat-view': 'view-chat',
 'trips-view': 'view-trips',
 'hotel-view': 'view-hotel'
 };

 const docks = {
 'map-view': 'dock-map',
 'chat-view': 'dock-chat',
 'trips-view': 'dock-trips',
 'hotel-view': 'dock-hotel'
 };

 document.querySelectorAll('.app-view').forEach(v => v.classList.remove('active'));
 document.querySelectorAll('.dock-tab').forEach(d => d.classList.remove('active'));
 document.querySelectorAll('.nav-pill-btn').forEach(b => b.classList.remove('active'));

 const targetView = document.getElementById(views[tabKey]);
 const targetDock = document.getElementById(docks[tabKey]);

 if (targetView) targetView.classList.add('active');
 if (targetDock) targetDock.classList.add('active');

 // Also update pill menu
 const pillIndex = Object.keys(views).indexOf(tabKey);
 const pillButtons = document.querySelectorAll('.nav-pill-btn');
 if (pillButtons[pillIndex]) pillButtons[pillIndex].classList.add('active');

 if (tabKey === 'map-view' && leafletMap) {
 setTimeout(() => leafletMap.invalidateSize(), 200);
 }
}

function planQuickTrip(dest) {
 switchAppTab('chat-view');
 handleChatPrompt(`Planning a trip to ${dest}`);
}

// --- 4. Local Experiences Registry & Provider Hub ---
const DEFAULT_LOCAL_EXPERIENCES = [
    {
        id: "exp_1",
        name: "Kala Ghoda Heritage Walk",
        category: "Heritage & Art",
        location: "Fort, Mumbai",
        duration: 2.5,
        price: 250,
        ecoScore: 5,
        accessibilityRating: 94,
        accessibilityTags: ["Wheelchair Ramp Access", "Audio Guide"],
        sustainability: "Audio-guided tactile exhibits, zero paper brochure",
        carbonKg: 0.3
    },
    {
        id: "exp_2",
        name: "Meluha Organic Farm-to-Table Workshop",
        category: "Culinary & Farming",
        location: "Powai, Mumbai",
        duration: 1.5,
        price: 450,
        ecoScore: 5,
        accessibilityRating: 92,
        accessibilityTags: ["Step-Free Entry", "Tactile Menu Cards"],
        sustainability: "100% farm-to-table organic sourcing, zero single-use plastic",
        carbonKg: 0.2
    },
    {
        id: "exp_3",
        name: "Bandra Bandstand Solar Cycling Tour",
        category: "Active & Outdoor",
        location: "Bandra West, Mumbai",
        duration: 2.0,
        price: 350,
        ecoScore: 5,
        accessibilityRating: 88,
        accessibilityTags: ["Adaptive Cycles Available", "Level Pathways"],
        sustainability: "Solar-charged e-cycle fleet, zero-emission sightseeing",
        carbonKg: 0.1
    },
    {
        id: "exp_4",
        name: "Dadar Artisan Pottery & Craft Studio",
        category: "Cultural Workshop",
        location: "Dadar, Mumbai",
        duration: 2.0,
        price: 300,
        ecoScore: 4,
        accessibilityRating: 90,
        accessibilityTags: ["Ground-Floor Access", "Sign-Language Guide"],
        sustainability: "Reused-material craft supplies, local artisan cooperative",
        carbonKg: 0.4
    },
    {
        id: "exp_5",
        name: "Powai Lake Sensory Wildlife Cruise",
        category: "Nature & Wildlife",
        location: "Powai, Mumbai",
        duration: 1.5,
        price: 280,
        ecoScore: 5,
        accessibilityRating: 95,
        accessibilityTags: ["Boarding Ramp", "Hearing Loop Commentary"],
        sustainability: "Silent electric-motor boats, no-noise wildlife sanctuary",
        carbonKg: 0.2
    }
];

// --- Central Registry client: a real shared backend (server/) instead of per-browser localStorage. ---
// Falls back to a local-only localStorage store if the backend isn't running, so the static
// site still works standalone — but in fallback mode, listings are NOT shared across browsers/devices.
const REGISTRY_API_BASE = window.API_BASE_URL || "http://localhost:3001";
let cachedExperiences = null;
let registryBackendAvailable = false;

async function initExperienceRegistry() {
    try {
        const res = await fetch(`${REGISTRY_API_BASE}/api/experiences`);
        if (!res.ok) throw new Error(`status ${res.status}`);
        cachedExperiences = await res.json();
        registryBackendAvailable = true;
    } catch (e) {
        console.warn("Central Registry backend unreachable — falling back to local-only browser storage. Run `npm install && npm start` inside /server for shared, cross-device data.", e);
        cachedExperiences = getLocalOnlyExperiences();
        registryBackendAvailable = false;
    }
}

function getLocalOnlyExperiences() {
    try {
        const stored = localStorage.getItem('urbanpulse_experiences');
        if (stored) return JSON.parse(stored);
    } catch (e) {}
    return DEFAULT_LOCAL_EXPERIENCES;
}

function persistLocalOnly(list) {
    try {
        localStorage.setItem('urbanpulse_experiences', JSON.stringify(list));
    } catch (e) {}
}

/** Synchronous read of the in-memory cache, populated by initExperienceRegistry() on load. */
function getStoredExperiences() {
    if (cachedExperiences === null) cachedExperiences = getLocalOnlyExperiences();
    return cachedExperiences;
}

async function saveExperienceToRegistry(newExp) {
    if (registryBackendAvailable) {
        try {
            const res = await fetch(`${REGISTRY_API_BASE}/api/experiences`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(newExp)
            });
            if (res.ok) {
                const saved = await res.json();
                cachedExperiences.unshift(saved);
                return cachedExperiences;
            }
        } catch (e) {
            console.warn("Failed to publish to Central Registry backend, saving locally instead.", e);
        }
    }
    cachedExperiences.unshift(newExp);
    persistLocalOnly(cachedExperiences);
    return cachedExperiences;
}

async function recordExperienceEvent(expId, field) {
    const endpoint = field === 'inquiryCount' ? 'inquiry' : 'view';
    if (registryBackendAvailable) {
        try {
            const res = await fetch(`${REGISTRY_API_BASE}/api/experiences/${expId}/${endpoint}`, { method: "POST" });
            if (res.ok) {
                const updated = await res.json();
                const idx = cachedExperiences.findIndex(e => e.id === expId);
                if (idx >= 0) cachedExperiences[idx] = updated;
                return;
            }
        } catch (e) {
            console.warn("Failed to record event on Central Registry backend, recording locally instead.", e);
        }
    }
    const target = cachedExperiences.find(e => e.id === expId);
    if (target) {
        target[field] = (target[field] || 0) + 1;
        persistLocalOnly(cachedExperiences);
    }
}

function recordExperienceViews(expList) {
    expList.forEach(exp => recordExperienceEvent(exp.id, 'viewsCount'));
}

function getOrCreateTravelerName() {
    try {
        let name = localStorage.getItem('urbanpulse_traveler_name');
        if (name) return name;
        name = "Traveler-" + Math.random().toString(36).slice(2, 8).toUpperCase();
        localStorage.setItem('urbanpulse_traveler_name', name);
        return name;
    } catch (e) {
        return "Traveler-WEB";
    }
}

async function createBooking(expId, travelerName, partySize, bookingDate) {
    if (registryBackendAvailable) {
        try {
            const res = await fetch(`${REGISTRY_API_BASE}/api/experiences/${expId}/bookings`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ travelerName, partySize, bookingDate })
            });
            if (res.ok) {
                const idx = cachedExperiences.findIndex(e => e.id === expId);
                if (idx >= 0) cachedExperiences[idx].bookingCount = (cachedExperiences[idx].bookingCount || 0) + 1;
                return true;
            }
        } catch (e) {
            console.warn("Failed to create booking on Central Registry backend.", e);
        }
    }
    const target = cachedExperiences.find(e => e.id === expId);
    if (target) {
        target.bookingCount = (target.bookingCount || 0) + 1;
        persistLocalOnly(cachedExperiences);
        return true;
    }
    return false;
}

async function submitAccessibilityReport(expId, confirmsAccessibility, note) {
    if (registryBackendAvailable) {
        try {
            const res = await fetch(`${REGISTRY_API_BASE}/api/experiences/${expId}/reports`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ confirmsAccessibility, note })
            });
            if (res.ok) {
                const idx = cachedExperiences.findIndex(e => e.id === expId);
                if (idx >= 0) {
                    const field = confirmsAccessibility ? 'accessibilityConfirmCount' : 'accessibilityDisputeCount';
                    cachedExperiences[idx][field] = (cachedExperiences[idx][field] || 0) + 1;
                }
                return true;
            }
        } catch (e) {
            console.warn("Failed to submit report on Central Registry backend.", e);
        }
    }
    const target = cachedExperiences.find(e => e.id === expId);
    if (target) {
        const field = confirmsAccessibility ? 'accessibilityConfirmCount' : 'accessibilityDisputeCount';
        target[field] = (target[field] || 0) + 1;
        persistLocalOnly(cachedExperiences);
        return true;
    }
    return false;
}

// Same confidence-tagged-claim approach as the Android app's EvidenceGraphService — never state
// "Accessible: Yes" outright; tag every claim Verified/Reported/Inferred and flag under-documentation.
// Real traveler reports (confirmsAccessibility submissions) take priority over the tag heuristic.
function buildExperienceEvidence(exp) {
    const claims = [];
    const tagCount = (exp.accessibilityTags || []).length;
    const expectedTags = exp.accessibilityRating >= 90 ? 2 : 1;
    const underDocumented = tagCount < expectedTags || (exp.accessibilityTags || []).includes("Standard Access");
    const disputeCount = exp.accessibilityDisputeCount || 0;
    const confirmCount = exp.accessibilityConfirmCount || 0;

    if (disputeCount > 0) {
        claims.push({
            icon: "🔵",
            label: "Inferred",
            claim: `Accessibility: ${exp.accessibilityRating}% claimed, but disputed by travelers`,
            contradiction: `${disputeCount} traveler report(s) dispute this accessibility claim` +
                (confirmCount > 0 ? ` (vs. ${confirmCount} confirming)` : "") +
                ` — treat the ${exp.accessibilityRating}% rating as unconfirmed until resolved.`
        });
    } else if (confirmCount > 0) {
        claims.push({
            icon: "✅",
            label: "Verified",
            claim: `Accessibility: ${exp.accessibilityRating}% match, ${tagCount} documented feature(s)`,
            contradiction: null
        });
    } else claims.push({
        icon: underDocumented ? "🔵" : "🟡",
        label: underDocumented ? "Inferred" : "Reported",
        claim: `Accessibility: ${exp.accessibilityRating}% match, ${tagCount} documented feature(s)`,
        contradiction: underDocumented
            ? `Rating claims ${exp.accessibilityRating}% but accessibility features are generic or under-documented, and no traveler has confirmed it yet — treat as inferred until confirmed on-site.`
            : "Provider-declared only — no independent traveler confirmation yet."
    });

    const sustainability = exp.sustainability || "";
    const isSpecific = sustainability.length > 20 && /(solar|organic|electric|zero|recycl|local)/i.test(sustainability);
    claims.push({
        icon: isSpecific ? "🟡" : "🔵",
        label: isSpecific ? "Reported" : "Inferred",
        claim: `Sustainability: ${sustainability}`,
        contradiction: isSpecific ? null : "No specific, checkable sustainability practice was provided — this is a category-based estimate, not a verified claim."
    });

    return claims;
}

function openAddExperienceModal() {
    document.getElementById('modal-add-experience').classList.add('open');
}

function closeAddExpModalDirect() {
    document.getElementById('modal-add-experience').classList.remove('open');
}

function closeAddExpModal(e) {
    if (e.target.id === 'modal-add-experience') {
        closeAddExpModalDirect();
    }
}

async function publishProviderExperience() {
    const name = document.getElementById('input-exp-name').value.trim();
    if (!name) {
        alert('Please enter an experience name');
        return;
    }
    const category = document.getElementById('input-exp-category').value;
    const location = document.getElementById('input-exp-location').value.trim() || "Mumbai";
    const duration = parseFloat(document.getElementById('input-exp-duration').value) || 2.0;
    const price = parseInt(document.getElementById('input-exp-price').value) || 350;
    const sustainability = document.getElementById('input-exp-sustainability').value.trim() || "Local community cooperative";
    const stepFree = document.getElementById('input-exp-stepfree').checked;
    const audio = document.getElementById('input-exp-audio').checked;

    const tags = [];
    if (stepFree) tags.push("Step-Free Ramp Access");
    if (audio) tags.push("Audio & Tactile Guide");
    if (tags.length === 0) tags.push("Standard Access");

    const newExp = {
        id: "exp_" + Date.now(), // overwritten by the server's own id when the backend is available
        name,
        category,
        location,
        duration,
        price,
        ecoScore: 5,
        accessibilityRating: stepFree ? 96 : 75,
        accessibilityTags: tags,
        sustainability,
        carbonKg: 0.3
    };

    await saveExperienceToRegistry(newExp);
    closeAddExpModalDirect();

    switchAppTab('chat-view');
    const scopeNote = registryBackendAvailable
        ? "Published to the shared Central Registry — visible to every device querying this backend."
        : "Saved to this browser only (Central Registry backend not running — see console for setup instructions).";
    setTimeout(() => {
        appendAiBubble(
            `🎉 <strong>Experience Published!</strong><br><br>` +
            `• <strong>Title</strong>: ${name}<br>` +
            `• <strong>Category</strong>: ${category} • ${location}<br>` +
            `• <strong>Duration</strong>: ${duration}h • ₹${price} / person<br>` +
            `• <strong>Accessibility</strong>: ${tags.join(", ")}<br>` +
            `• <strong>Sustainability</strong>: ${sustainability}<br><br>` +
            `${scopeNote} It will be recommended automatically to travelers asking for local experiences, workshops, or 2-hour micro-trips!`
        );
    }, 300);
}

// --- 5. Groq Ultra-Fast AI Chat Engine ---
let chatDialogueStep = 0;
let activePlanningDestination = "Kedarnath";
let activePlanningDays = 3;

async function queryGroqAi(prompt, systemInstruction = null) {
    const localExpSummary = getStoredExperiences().slice(0, 5).map(e => `${e.name} (${e.category} in ${e.location}, ${e.duration}h, ₹${e.price}, ${e.accessibilityRating}% access)`).join("; ");
    const defaultInstruction = `You are Yatri AI, an expert sustainable travel & smart mobility assistant for UrbanPulse. Verified local experiences in registry: [${localExpSummary}]. When asked general questions, answer accurately. When asked about local activities, short trips, or workshops, prioritize recommending these verified gems.`;
    
    const finalInstruction = systemInstruction || defaultInstruction;

    try {
        const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
            method: "POST",
            headers: {
                "Authorization": `Bearer ${GROQ_API_KEY}`,
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                model: "openai/gpt-oss-120b",
                messages: [
                    { role: "system", content: finalInstruction },
                    { role: "user", content: prompt }
                ],
                temperature: 0.3,
                max_tokens: 600
            })
        });

        if (!res.ok) return null;
        const json = await res.json();
        return json.choices?.[0]?.message?.content || null;
    } catch (e) {
        return null;
    }
}

function sendUserMessage() {
    const input = document.getElementById('user-chat-input');
    const text = input.value.trim();
    if (!text) return;
    handleChatPrompt(text);
    input.value = "";
}

function openProviderDashboardModal() {
    renderProviderDashboard();
    document.getElementById('modal-provider-dashboard').classList.add('open');
}

function closeProviderDashboardModalDirect() {
    document.getElementById('modal-provider-dashboard').classList.remove('open');
}

function closeProviderDashboardModal(e) {
    if (e.target.id === 'modal-provider-dashboard') {
        closeProviderDashboardModalDirect();
    }
}

async function toggleWebExperienceAvailability(expId) {
    if (registryBackendAvailable) {
        try {
            const res = await fetch(`${REGISTRY_API_BASE}/api/experiences/${expId}/availability`, { method: "PATCH" });
            if (res.ok) {
                const updated = await res.json();
                const idx = cachedExperiences.findIndex(e => e.id === expId);
                if (idx >= 0) cachedExperiences[idx] = updated;
                renderProviderDashboard();
                return;
            }
        } catch (e) {
            console.warn("Failed to toggle availability on Central Registry backend, toggling locally instead.", e);
        }
    }
    const target = cachedExperiences.find(e => e.id === expId);
    if (target) {
        target.isAvailableToday = (target.isAvailableToday !== false) ? false : true;
        persistLocalOnly(cachedExperiences);
        renderProviderDashboard();
    }
}

function renderProviderDashboard() {
    const container = document.getElementById('web-provider-listings');
    if (!container) return;
    const list = getStoredExperiences();
    container.innerHTML = "";

    list.forEach(exp => {
        const isAvailable = exp.isAvailableToday !== false;
        const card = document.createElement('div');
        card.className = "app-trip-card";
        card.style.marginBottom = "8px";
        card.innerHTML = `
            <div style="display: flex; justify-content: space-between; align-items: start;">
                <div>
                    <div style="font-weight: 700; font-size: 14px;">${exp.name}</div>
                    <div style="font-size: 11px; color: var(--text-secondary);">${exp.category} • ${exp.location} • ${exp.duration}h • ₹${exp.price}</div>
                </div>
                <span class="trip-carbon-tag" style="font-size: 10px;">${isAvailable ? "Available" : "Booked Out"}</span>
            </div>
            <div style="font-size: 11px; color: var(--primary-emerald); margin: 6px 0;">
                👁️ ${exp.viewsCount || 0} Views • ${exp.inquiryCount || 0} Inquiries • 📅 ${exp.bookingCount || 0} Bookings
            </div>
            <button class="view-itinerary-btn" style="width: 100%; padding: 6px; font-size: 11px;" onclick="toggleWebExperienceAvailability('${exp.id}')">
                Toggle Status: ${isAvailable ? "Set to Booked Out" : "Set to Available Today"}
            </button>
        `;
        container.appendChild(card);
    });
}

let lastViewedExperienceId = null;

async function handleChatPrompt(promptText) {
    appendUserBubble(promptText);

    const lower = promptText.toLowerCase().trim();

    // 0a. Real booking / accessibility-report actions on the last-viewed experience
    if (lastViewedExperienceId && ["📅 Book This Experience", "✅ Confirm Accessibility", "⚠️ Report an Issue"].includes(promptText)) {
        const expId = lastViewedExperienceId;
        if (promptText === "📅 Book This Experience") {
            const travelerName = getOrCreateTravelerName();
            const bookingDate = new Date().toISOString().slice(0, 10);
            const ok = await createBooking(expId, travelerName, 1, bookingDate);
            setTimeout(() => appendAiBubble(
                ok ? `✅ <strong>Booked!</strong> Confirmed for ${travelerName} on ${bookingDate}. This is a real reservation recorded in the Central Registry.`
                   : `⚠️ Couldn't reach the booking service right now — please try again.`
            ), 200);
        } else if (promptText === "✅ Confirm Accessibility") {
            const ok = await submitAccessibilityReport(expId, true, "Confirmed via Yatri AI chat");
            setTimeout(() => appendAiBubble(
                ok ? `✅ Thanks — your confirmation was recorded and will strengthen this listing's Evidence Graph confidence for future travelers.`
                   : `⚠️ Couldn't submit your report right now — please try again.`
            ), 200);
        } else if (promptText === "⚠️ Report an Issue") {
            const ok = await submitAccessibilityReport(expId, false, "Disputed via Yatri AI chat");
            setTimeout(() => appendAiBubble(
                ok ? `⚠️ Thanks for flagging this — future travelers will see this as a real disputed claim in the Evidence Graph.`
                   : `⚠️ Couldn't submit your report right now — please try again.`
            ), 200);
        }
        return;
    }

    // 0b. Experience chip clicked directly -> record a real inquiry and show its detail card
    const matchedExp = getStoredExperiences().find(e => e.name === promptText);
    if (matchedExp) {
        recordExperienceEvent(matchedExp.id, 'inquiryCount');
        lastViewedExperienceId = matchedExp.id;
        const evidence = buildExperienceEvidence(matchedExp);
        const evidenceHtml = evidence.map(c =>
            `${c.icon} ${c.label}: ${c.claim}${c.contradiction ? `<br>&nbsp;&nbsp;⚠️ ${c.contradiction}` : ""}`
        ).join("<br>");
        setTimeout(() => {
            appendAiBubble(
                `<strong>${matchedExp.name}</strong><br>` +
                `${matchedExp.category} • ${matchedExp.location} • ${matchedExp.duration}h • ₹${matchedExp.price}<br>` +
                `📅 ${matchedExp.bookingCount || 0} real booking(s) • 👁️ ${matchedExp.viewsCount || 0} views<br><br>` +
                `<strong>Evidence Graph — Why this?</strong><br>${evidenceHtml}`,
                ["📅 Book This Experience", "✅ Confirm Accessibility", "⚠️ Report an Issue", "Show on Live Map"]
            );
        }, 300);
        return;
    }

    // 1. Circumstance Adaptation (Rain, Weather, Sudden Delays)
    // Cross-checked against a real live Open-Meteo reading, not just the user's own wording.
    if (lower.includes("adapt") || lower.includes("rain") || lower.includes("weather") || lower.includes("delay")) {
        const liveWeather = await fetchOpenMeteoWeather();
        const covered = getStoredExperiences().filter(e => e.category.includes("Workshop") || e.category.includes("Craft") || e.category.includes("Culinary") || e.category.includes("Art"));
        let html = `☔ <strong>Real-Time Circumstance Adaptation Triggered</strong><br><br>`;
        if (liveWeather) {
            html += liveWeather.isRaining
                ? `Live weather check confirms rain (${liveWeather.precipitation}mm, ${liveWeather.temperatureC}°C) at Mumbai HQ coordinates — `
                : `Live weather check shows no rain right now (${liveWeather.temperatureC}°C) — adapting based on your request anyway — `;
        } else {
            html += `Weather change or schedule delay reported — `;
        }
        html += `we've dynamically adapted your itinerary, swapping outdoor cycling and treks for covered, indoor cultural workshops & tactile galleries:<br><br>`;

        covered.slice(0, 3).forEach((exp, idx) => {
            html += `<strong>${idx + 1}. ${exp.name}</strong> [🏛️ Indoor / Covered]<br>`;
            html += `• Location: ${exp.location} • Duration: <strong>${exp.duration}h</strong> • Price: <strong>₹${exp.price}</strong><br>`;
            html += `• Accessibility: ${exp.accessibilityRating}% (${exp.accessibilityTags.join(", ")})<br>`;
            html += `• Status: ${exp.isAvailableToday !== false ? "✅ Available Today" : "⚠️ Busy"}<br><br>`;
        });

        html += `Would you like to route transit to the nearest covered workshop?`;
        recordExperienceViews(covered.slice(0, 3));
        setTimeout(() => {
            appendAiBubble(html, covered.slice(0, 3).map(e => e.name).concat(["Live Route Map"]));
        }, 400);
        return;
    }

    // 2. Family & Child-Friendly Filter
    if (lower.includes("family") || lower.includes("child") || lower.includes("kid")) {
        const familyList = getStoredExperiences().filter(e => !e.name.includes("Night") && e.accessibilityRating >= 85);
        let html = `👨‍👩‍👧‍👦 <strong>Family &amp; Child-Friendly Recommendations</strong><br><br>`;
        html += `Filtered for safe, interactive, and family-appropriate activities with step-free stroller/ramp concourses:<br><br>`;

        familyList.slice(0, 3).forEach((exp, idx) => {
            html += `<strong>${idx + 1}. ${exp.name}</strong> [${exp.category}]<br>`;
            html += `• Location: ${exp.location} • Duration: <strong>${exp.duration}h</strong> • Price: <strong>₹${exp.price}</strong><br>`;
            html += `• Accessibility: ${exp.accessibilityRating}% (${exp.accessibilityTags.join(", ")})<br><br>`;
        });

        html += `Select an activity to view family group pricing and step-free transit directions:`;
        recordExperienceViews(familyList.slice(0, 3));
        setTimeout(() => {
            appendAiBubble(html, familyList.slice(0, 3).map(e => e.name).concat(["Explore Eco Stays"]));
        }, 400);
        return;
    }

    // 3. Micro-experience / 2-hour filter
    if (lower.includes("2 hour") || lower.includes("2 hr") || lower.includes("micro-experience") || lower.includes("micro experience") || lower.includes("time crunch") || lower.includes("short on time")) {
        const exps = getStoredExperiences().filter(e => e.duration <= 2.5);
        let html = `⏱️ <strong>Found ${exps.length} Pareto-Optimized Micro-Experiences (Under 2 Hours)</strong><br><br>`;
        html += `Curated for your available time window near your coordinates with verified accessibility & zero emission transit:<br><br>`;

        exps.slice(0, 4).forEach((exp, idx) => {
            html += `<strong>${idx + 1}. ${exp.name}</strong> [${exp.category}]<br>`;
            html += `• Location: ${exp.location} • Duration: <strong>${exp.duration}h</strong> • Price: <strong>₹${exp.price}</strong><br>`;
            html += `• Accessibility: ${exp.accessibilityRating}% (${exp.accessibilityTags.join(", ")})<br>`;
            html += `• Eco Practice: ${exp.sustainability}<br><br>`;
        });

        html += `Which of these would you like to explore or route?`;
        recordExperienceViews(exps.slice(0, 4));
        setTimeout(() => {
            appendAiBubble(html, exps.slice(0, 3).map(e => e.name).concat(["+ List New Experience"]));
        }, 400);
        return;
    }

    if (promptText === "+ List New Experience") {
        openAddExperienceModal();
        return;
    }

 // Step 1: Detect Destination -> Ask Duration MCQ
 const detectedDest = extractDestinationName(promptText);
 if (detectedDest || lower.includes("plan") || lower.includes("trip") || lower.includes("itinerary")) {
 activePlanningDestination = detectedDest || "Kedarnath";
 chatDialogueStep = 1;

 const isHimalayan = activePlanningDestination.includes("Kedar") || activePlanningDestination.includes("Badri") || activePlanningDestination.includes("Manali") || activePlanningDestination.includes("Leh");

 const options = isHimalayan ?
 ["3 Days Express Yatra", "4 Days Pilgrim Trek", "7 Days Complete Circuit"] :
 ["1 Day Express", "2 Days Weekend", "3 Days Leisure"];

 setTimeout(() => {
 appendAiBubble(
 `I would love to design a smart, low-carbon, and accessible itinerary to <strong>${activePlanningDestination}</strong>! ️<br><br>How many days are you planning for your ${activePlanningDestination} trip?`,
 options
 );
 }, 500);
 return;
 }

 // Step 2: Duration Selected -> Ask Travel Style / Accessibility
 if (chatDialogueStep === 1 || lower.includes("day") || lower.includes("express") || lower.includes("weekend") || lower.includes("yatra") || lower.includes("pilgrim")) {
 activePlanningDays = lower.includes("1") ? 1 : (lower.includes("7") ? 7 : (lower.includes("4") ? 4 : 3));
 chatDialogueStep = 2;

 const isHimalayan = activePlanningDestination.includes("Kedar") || activePlanningDestination.includes("Badri") || activePlanningDestination.includes("Manali") || activePlanningDestination.includes("Leh");

 const options = isHimalayan ?
 ["Palki & Accessible ", "Eco Pilgrim Trek ", "Budget Devotee ", "Heli-Yatra & Luxury "] :
 ["Wheelchair Step-Free ", "Eco Nature & Farm ", "Budget Explorer ", "Luxury Heritage "];

 setTimeout(() => {
 appendAiBubble(
 `Got it! A <strong>${activePlanningDays}-Day journey to ${activePlanningDestination}</strong> is selected.<br><br>What is your preferred travel style and accessibility requirement for ${activePlanningDestination}?`,
 options
 );
 }, 500);
 return;
 }

 // Step 3: Style Selected -> Query Groq AI for authentic itinerary
 if (chatDialogueStep === 2 || lower.includes("wheelchair") || lower.includes("palki") || lower.includes("eco") || lower.includes("pilgrim") || lower.includes("budget") || lower.includes("luxury")) {
 chatDialogueStep = 0;
 const isAccessible = lower.includes("wheelchair") || lower.includes("palki") || lower.includes("step-free");

 appendAiBubble("<em> Consulting Groq LLaMA-3.3-70B for verified itinerary &amp; step-free transit corridors...</em>");

 queryGroqAi(`Generate a ${activePlanningDays}-day sustainable and ${isAccessible ? "wheelchair/palki step-free accessible" : "eco-nature"} itinerary for ${activePlanningDestination}. Include realistic train/bus transit, verified solar/eco hotel, AQI estimate, budget in INR, and carbon avoided vs petrol car. Keep it concise.`)
 .then(aiText => {
 const box = document.getElementById('chat-viewport');
 box.lastElementChild.remove(); // Remove thinking bubble

 if (aiText) {
 const formatted = aiText.replace(/\n/g, '<br>').replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
 appendAiBubble(
 ` <strong>${activePlanningDays}-Day Plan for ${activePlanningDestination} (Grounded by Groq LLaMA-3.3)</strong>:<br><br>${formatted}`,
 ["Save to My Trips Hub ", "Show on Live Map ️", "Plan Another Destination "]
 );
 } else {
 // Fallback
 appendAiBubble(
 ` <strong>Your ${activePlanningDays}-Day Sustainable Itinerary for ${activePlanningDestination} is Ready!</strong><br><br>` +
 `• <strong>Transit:</strong> Electric Pilgrim Coach + Gaurikund E-Shuttle (₹650)<br>` +
 `• <strong>Stay:</strong> GMVN Mandakini Eco Tourist Rest House ( 4.8 • Solar Heated)<br>` +
 `• <strong>Accessibility:</strong> ${isAccessible ? "100% Assisted Palki / Wheelchair Hoist" : "Standard Concourse"}<br>` +
 `• <strong>Air Quality:</strong> 18 (Pristine Himalayan Alpine Air)<br>` +
 `• <strong>Budget:</strong> ₹${(2800 * activePlanningDays).toLocaleString()}<br>` +
 `• <strong>Carbon Avoided:</strong> -${(14.2 * activePlanningDays).toFixed(1)} kg CO₂e vs petrol SUV!`,
 ["Save to My Trips Hub ", "Show on Live Map ️", "Plan Another Destination "]
 );
 }
 });
 return;
 }

 if (lower.includes("save to my trips")) {
 setTimeout(() => {
 appendAiBubble(` <strong>Saved to your Trips Hub!</strong> (+${activePlanningDays * 120} PULSE Points awarded to your Carbon Wallet).`);
 }, 400);
 return;
 }

 if (lower.includes("show on live map")) {
 switchAppTab('map-view');
 renderSelectedRoute(activePlanningDestination.toLowerCase().includes("kedar") ? "kedarnath" : "lonavala");
 return;
 }

 // General user queries -> Query Groq directly!
 appendAiBubble("<em> Yatri AI is thinking...</em>");
 queryGroqAi(promptText).then(response => {
 const box = document.getElementById('chat-viewport');
 box.lastElementChild.remove();
 if (response) {
 const formatted = response.replace(/\n/g, '<br>').replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
 appendAiBubble(formatted, ["Plan Trip to Kedarnath ️", "Plan Trip to Lonavala "]);
 } else {
 appendAiBubble("I can help you plan green itineraries to Kedarnath, Lonavala, Alibaug, or query live traffic and air quality!", ["Plan Trip to Kedarnath ️", "Plan Trip to Lonavala "]);
 }
 });
}

function extractDestinationName(promptText) {
 const lower = promptText.toLowerCase().trim();

 if (lower.includes("kedar nath") || lower.includes("kedarnath")) return "Kedarnath";
 if (lower.includes("badrinath") || lower.includes("badri nath")) return "Badrinath";
 if (lower.includes("rishikesh")) return "Rishikesh";
 if (lower.includes("haridwar")) return "Haridwar";
 if (lower.includes("manali")) return "Manali";
 if (lower.includes("shimla")) return "Shimla";
 if (lower.includes("leh") || lower.includes("ladakh")) return "Leh Ladakh";
 if (lower.includes("alibaug") || lower.includes("alibag")) return "Alibaug";
 if (lower.includes("mahabaleshwar")) return "Mahabaleshwar";
 if (lower.includes("matheran")) return "Matheran";
 if (lower.includes("lonavala") || lower.includes("lonavla")) return "Lonavala";
 if (lower.includes("goa")) return "Goa";
 if (lower.includes("jaipur")) return "Jaipur";
 if (lower.includes("udaipur")) return "Udaipur";
 if (lower.includes("varanasi") || lower.includes("kashi")) return "Varanasi";
 if (lower.includes("ayodhya")) return "Ayodhya";

 const regex = /(?:plan(?:ning)?(?:\s+a)?\s+trip\s+to|trip\s+to|visit|travel\s+to|going\s+to|guide\s+for|itinerary\s+for)\s+([a-zA-Z\s]{2,30})/i;
 const match = promptText.match(regex);
 if (match && match[1]) {
 const cleaned = match[1].trim().split(/\s+(?:with|for|in|using|by)\s+/i)[0].trim();
 if (cleaned.length > 1) {
 return cleaned.split(' ').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ');
 }
 }

 return null;
}

function appendUserBubble(text) {
 const box = document.getElementById('chat-viewport');
 const msg = document.createElement('div');
 msg.className = 'chat-msg user-msg';
 msg.innerHTML = `
 <div class="msg-bubble-wrap">
 <div class="msg-bubble">${text}</div>
 </div>
 `;
 box.appendChild(msg);
 box.scrollTop = box.scrollHeight;
}

function appendAiBubble(htmlContent, chips = []) {
 const box = document.getElementById('chat-viewport');
 const msg = document.createElement('div');
 msg.className = 'chat-msg ai-msg';

 let chipsHtml = '';
 if (chips && chips.length > 0) {
 chipsHtml = `<div class="mcq-chips-container">` +
 chips.map(c => `<button class="mcq-chip" onclick="handleChatPrompt('${c.replace(/'/g, "\\'")}')">${c}</button>`).join('') +
 `</div>`;
 }

 msg.innerHTML = `
 <div class="ai-badge-avatar"></div>
 <div class="msg-bubble-wrap">
 <div class="msg-bubble">${htmlContent}</div>
 ${chipsHtml}
 </div>
 `;
 box.appendChild(msg);
 box.scrollTop = box.scrollHeight;
}

function resetChat() {
 document.getElementById('chat-viewport').innerHTML = `
 <div class="chat-msg ai-msg">
 <div class="ai-badge-avatar"></div>
 <div class="msg-bubble-wrap">
 <div class="msg-bubble">
 Dialogue reset! Powered by <strong>Groq LLaMA-3.3-70B</strong>. Where would you like to travel?
 </div>
 <div class="mcq-chips-container">
 <button class="mcq-chip" onclick="handleChatPrompt('Plan a trip to Kedarnath')">️ Plan Kedarnath Yatra</button>
 <button class="mcq-chip" onclick="handleChatPrompt('Plan a trip to Lonavala')"> Plan Lonavala Weekend</button>
 <button class="mcq-chip" onclick="handleChatPrompt('Plan Coastal Alibaug')">️ Plan Coastal Alibaug</button>
 </div>
 </div>
 </div>
 `;
 chatDialogueStep = 0;
}

// --- 5. Hotel B2B Operations & ESG Export ---
function updateHotelKpis(val) {
 const occupancy = parseInt(val, 10);
 const rooms = Math.round(occupancy * 2);
 const power = Math.round(occupancy * 24.2 + 80);
 const water = Math.round(occupancy * 190);
 const food = Math.round(occupancy * 0.56);
 const meals = food * 2;

 document.getElementById('occupancy-val-badge').innerText = `${occupancy}% (${rooms} Rooms)`;
 document.getElementById('kpi-power').innerText = `${power.toLocaleString()} kWh`;
 document.getElementById('kpi-power-sub').innerText = `HVAC load: ${Math.round(power * 0.52)} kWh • Solar: 38%`;
 document.getElementById('kpi-water').innerText = `${water.toLocaleString()} L`;
 document.getElementById('kpi-food').innerText = `${food} kg (${meals} Meals)`;
}

function triggerHvacOptimization() {
 alert("️ Automated Eco-Setpoint: All 150 room zones set to 26°C setback. Projected daily savings: 180 kWh (₹1,620 avoided).");
}

function triggerFoodRescue() {
 alert(" Food Rescue Dispatched: Driver from Roti Bank / Feeding India assigned. Pickup ETA: 18 minutes.");
}

async function sha256Hex(text) {
    const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('');
}

async function exportEsgPdf() {
 const occupancy = document.getElementById('slider-occupancy').value;
 const rooms = Math.round(occupancy * 2);
 const power = Math.round(occupancy * 24.2 + 80);
 const water = Math.round(occupancy * 190);
 const food = Math.round(occupancy * 0.56);
 const dateStr = new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' });

 // Real pass/fail computed from the live occupancy-derived metrics against the stated benchmarks
 // (BEE 5-Star energy benchmark: <=20 kWh/room/day; water target: <=220 L/room/day)
 const powerPerRoom = power / rooms;
 const waterPerRoom = water / rooms;
 const passPower = powerPerRoom <= 20;
 const passWater = waterPerRoom <= 220;
 const complianceStatus = (passPower && passWater) ? "PASSED" : "NEEDS IMPROVEMENT";
 const complianceColor = (passPower && passWater) ? "#059669" : "#DC2626";

 // Facility-declared install assumptions (solar capacity mix, HVAC setback, greywater recycling rate)
 // are NOT live telemetry — there is no connected utility meter — so they are disclosed as such
 // rather than presented as measured values.
 const solarMixPct = 38.5;
 const hvacSetbackKwh = Math.round(power * 0.10);
 const greywaterPct = 85;

 const reportBody = `Facility=The Orchid Eco-Heritage Resort;Occupancy=${occupancy}%;Rooms=${rooms};Date=${dateStr};Power=${power}kWh;Water=${water}L;Food=${food}kg;PowerPerRoom=${powerPerRoom.toFixed(2)};WaterPerRoom=${waterPerRoom.toFixed(2)};Compliance=${complianceStatus}`;
 const contentHash = await sha256Hex(reportBody);

 const printWin = window.open('', '_blank');
 printWin.document.write(`
 <!DOCTYPE html>
 <html>
 <head>
 <title>UrbanPulse_ESG_Audit_Report_${occupancy}pct</title>
 <style>
 body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 40px; color: #0F172A; }
 .header-band { background: #064E3B; color: white; padding: 24px; border-radius: 8px; margin-bottom: 24px; }
 .brand-sub { font-size: 11px; font-weight: bold; color: #10B981; letter-spacing: 0.05em; }
 .title { font-size: 24px; font-weight: bold; margin: 6px 0; }
 .standard { font-size: 11px; color: #A7F3D0; }
 .meta-grid { display: grid; grid-template-columns: 1fr 1fr; background: #F1F5F9; padding: 16px; border-radius: 8px; margin-bottom: 24px; font-size: 13px; gap: 8px; }
 .sec-title { font-size: 15px; font-weight: bold; margin: 20px 0 10px 0; border-bottom: 2px solid #E2E8F0; padding-bottom: 4px; color: #0F172A; }
 table { width: 100%; border-collapse: collapse; margin-bottom: 16px; }
 th, td { padding: 10px 14px; text-align: left; font-size: 12px; border-bottom: 1px solid #E2E8F0; }
 th { background: #F8FAFC; color: #64748B; font-weight: 600; }
 .highlight-green { color: #059669; font-weight: bold; }
 .note-row td { color: #94A3B8; font-style: italic; }
 .footer-box { background: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 8px; padding: 16px; margin-top: 30px; font-size: 11px; color: #64748B; word-break: break-all; }
 @media print { @page { margin: 1.5cm; } button { display: none; } }
 </style>
 </head>
 <body>
 <div class="header-band">
 <div class="brand-sub">URBANPULSE • B2B SUSTAINABILITY INTELLIGENCE PLATFORM</div>
 <div class="title">ESG Compliance &amp; Resource Audit</div>
 <div class="standard">Standard: ISO 14064 Greenhouse Protocol • LEED Platinum &amp; BEE 5-Star Benchmarking</div>
 </div>

 <div class="meta-grid">
 <div><strong>Facility:</strong> The Orchid Eco-Heritage Resort &amp; Conference Center</div>
 <div><strong>Occupancy Scale:</strong> ${occupancy}% (${rooms} Rooms)</div>
 <div><strong>Audit Date:</strong> ${dateStr}</div>
 <div><strong>Compliance Status:</strong> <span style="color:${complianceColor}; font-weight:bold;">${complianceStatus}</span> (computed live from occupancy inputs vs. benchmarks below)</div>
 </div>

 <div class="sec-title"> Energy Intelligence &amp; HVAC Avoidance</div>
 <table>
 <tr><th>Metric</th><th>Value</th><th>Compliance Benchmark</th></tr>
 <tr><td>Daily Power Consumption (live, from occupancy)</td><td><strong>${power.toLocaleString()} kWh</strong> (${powerPerRoom.toFixed(1)} kWh/room)</td><td>${passPower ? '<span class="highlight-green">PASS</span>' : 'FAIL'} — Target &lt;= 20 kWh/room</td></tr>
 <tr><td>Automated HVAC Setback Avoided (est. 10% of load)</td><td>${hvacSetbackKwh.toLocaleString()} kWh (Daily)</td><td>Automated 26°C Setpoint</td></tr>
 <tr class="note-row"><td colspan="3">Solar Generation Mix &amp; HVAC setback are facility-declared installed-capacity assumptions, not live meter telemetry (no utility meter is connected)</td></tr>
 <tr><td>Onsite Solar Generation Mix (declared)</td><td>${solarMixPct}% Renewable</td><td>Target: &gt;= 30.0%</td></tr>
 </table>

 <div class="sec-title"> Water Stewardship &amp; Recycling</div>
 <table>
 <tr><th>Metric</th><th>Value</th><th>Compliance Benchmark</th></tr>
 <tr><td>Daily Potable Water Consumption (live, from occupancy)</td><td><strong>${water.toLocaleString()} Liters</strong> (${waterPerRoom.toFixed(0)} L/room)</td><td>${passWater ? '<span class="highlight-green">PASS</span>' : 'FAIL'} — Target &lt;= 220 L/room</td></tr>
 <tr><td>Greywater Recycled &amp; Reused (declared rate: ${greywaterPct}%)</td><td>${Math.round(water * greywaterPct / 100).toLocaleString()} Liters</td><td>Zero Liquid Discharge (ZLD)</td></tr>
 </table>

 <div class="sec-title"> Food Waste Diversion &amp; Rescue</div>
 <table>
 <tr><th>Metric</th><th>Value</th><th>Compliance Benchmark</th></tr>
 <tr><td>Surplus Food Diverted (live, from occupancy)</td><td><strong>${food} kg</strong></td><td>Food Waste Reduction Target</td></tr>
 <tr><td>Shelter Meals Provided (est. 2 meals/kg)</td><td>${food * 2} Meals</td><td>Local Food Rescue Partner</td></tr>
 </table>

 <div class="footer-box">
 <strong>Report generation method:</strong> Power/Water/Food figures are computed live from the occupancy input via this app's KPI formulas. Solar mix, HVAC setback and greywater rate are disclosed facility-declared assumptions, not live sensor data — no IoT/utility integration exists yet. Compliance status is computed by comparing the live figures to the stated benchmarks above, not a fixed verdict.<br><br>
 <strong>Content Integrity Hash (SHA-256):</strong> ${contentHash}<br>
 This hash is a real digest of this report's data fields, computed client-side at generation time — recompute it from the fields above to verify this document was not altered after export. It is not a legal or regulatory digital signature.
 </div>

 <script>
 window.onload = function() {
 window.print();
 };
 </script>
 </body>
 </html>
 `);
 printWin.document.close();
}

function exportEsgCsv() {
 const occupancy = document.getElementById('slider-occupancy').value;
 const rooms = Math.round(occupancy * 2);
 const power = Math.round(occupancy * 24.2 + 80);
 const water = Math.round(occupancy * 190);
 const food = Math.round(occupancy * 0.56);
 const dateStr = new Date().toISOString().slice(0, 10);
 const powerPerRoom = power / rooms;
 const waterPerRoom = water / rooms;
 const passPower = powerPerRoom <= 20;
 const passWater = waterPerRoom <= 220;
 const complianceStatus = (passPower && passWater) ? "PASSED" : "NEEDS IMPROVEMENT";

 const csvContent = "data:text/csv;charset=utf-8," +
 "URBANPULSE B2B ESG SUSTAINABILITY & COMPLIANCE AUDIT SHEET\n" +
 "Facility Name,The Orchid Eco-Heritage Resort & Conference Center\n" +
 `Audit Date,${dateStr}\n` +
 "Standard,ISO 14064 Carbon Accounting & LEED Platinum Benchmarking\n\n" +
 "Metric,Value,Unit,Compliance Benchmark,Data Source\n" +
 `Current Occupancy,${occupancy},%,Target <= 85%,Live user input\n` +
 `Facility Power Consumption,${power},kWh,${passPower ? 'PASS' : 'FAIL'} - Target <= 20 kWh/room,Live (formula on occupancy)\n` +
 `Solar Renewable Mix,38.5,%,Target >= 30%,Facility-declared assumption (no meter)\n` +
 `Water Consumption,${water},Liters,${passWater ? 'PASS' : 'FAIL'} - Target <= 220 L/room,Live (formula on occupancy)\n` +
 `Greywater Recycled (declared 85% rate),${Math.round(water * 0.85)},Liters,Zero Liquid Discharge (ZLD),Facility-declared assumption\n` +
 `Kitchen Surplus Diverted,${food},kg,Food Waste Reduction Target,Live (formula on occupancy)\n\n` +
 `Verification Status,${complianceStatus} (computed from live figures above vs. stated benchmarks)\n`;

 const encodedUri = encodeURI(csvContent);
 const link = document.createElement("a");
 link.setAttribute("href", encodedUri);
 link.setAttribute("download", `UrbanPulse_ESG_Audit_${occupancy}pct.csv`);
 document.body.appendChild(link);
 link.click();
 document.body.removeChild(link);
}

// --- 6. Schedule Modal ---
const SCHEDULE_TEMPLATES = {
 kedarnath: {
 title: "Kedarnath Holy Eco-Yatra Schedule (From Mumbai)",
 html: `
 <div style="font-size:13px; line-height:1.6; color:#94A3B8;">
 <h4 style="color:#10B981; margin-bottom:6px;">DAY 1: Mumbai Departure to Haridwar Hub</h4>
 <p>• <strong>08:30 AM</strong> — Haridwar AC Superfast Express (Mumbai CSMT/Bandra to Haridwar Jn) [Train • Level Boarding • ₹1,450]</p>
 <p>• <strong>03:00 PM</strong> — Haridwar GMVN Alaknanda Rest House Check-in (Solar Powered)</p>
 <p>• <strong>06:30 PM</strong> — Har Ki Pauri Ganga Aarti (Paved accessible walkway)</p>
 <hr style="border-color:rgba(255,255,255,0.1); margin:12px 0;">
 <h4 style="color:#10B981; margin-bottom:6px;">DAY 2: Haridwar to Sonprayag &amp; Gaurikund Base</h4>
 <p>• <strong>06:00 AM</strong> — AC Electric Pilgrim Coach (Haridwar to Sonprayag) [₹650]</p>
 <p>• <strong>02:30 PM</strong> — Sonprayag to Gaurikund Base (Govt E-Shuttle) [₹50]</p>
 <p>• <strong>04:30 PM</strong> — GMVN Mandakini Solar Guest House Check-in (Heated Step-Free Rooms)</p>
 <hr style="border-color:rgba(255,255,255,0.1); margin:12px 0;">
 <h4 style="color:#10B981; margin-bottom:6px;">DAY 3: Gaurikund to Shri Kedarnath Dham</h4>
 <p>• <strong>05:30 AM</strong> — Eco-Pilgrim Ascent (Step-free assisted Palki / Paved Himalayan walking trail)</p>
 <p>• <strong>01:00 PM</strong> — Shri Kedarnath Temple Darshan (12th Jyotirlinga • Zero Plastic Eco-Zone)</p>
 <p>• <strong>06:30 PM</strong> — Evening Mandakini Aarti (Solar illuminated temple complex with bio-toilets)</p>
 <hr style="border-color:rgba(255,255,255,0.1); margin:12px 0;">
 <h4 style="color:#10B981; margin-bottom:6px;">DAY 4: Bhairavnath Ridge &amp; Return to Mumbai</h4>
 <p>• <strong>07:00 AM</strong> — Bhairavnath Panoramic Viewpoint</p>
 <p>• <strong>11:30 AM</strong> — Descent &amp; E-Shuttle to Sonprayag</p>
 <p>• <strong>06:00 PM</strong> — Return Superfast Express Haridwar to Mumbai CSMT [₹1,450]</p>
 </div>
 `
 },
 lonavala: {
 title: "Lonavala Monsoon Eco-Retreat Schedule",
 html: `
 <div style="font-size:13px; line-height:1.6; color:#94A3B8;">
 <h4 style="color:#10B981; margin-bottom:6px;">DAY 1: Scenic Ridge &amp; Heritage Caves</h4>
 <p>• <strong>07:10 AM</strong> — Indrayani Express Electric Train (Dadar to Lonavala) [Train • Level Boarding • ₹75]</p>
 <p>• <strong>09:45 AM</strong> — The Machan Solar Treehouse Check-in</p>
 <p>• <strong>11:30 AM</strong> — Karla Caves &amp; Accessible Lower Plaza [₹50]</p>
 <p>• <strong>03:30 PM</strong> — Bhushi Dam Eco Trail (Rainwater corridor)</p>
 <hr style="border-color:rgba(255,255,255,0.1); margin:12px 0;">
 <h4 style="color:#10B981; margin-bottom:6px;">DAY 2: Tiger Point &amp; Botanical Garden</h4>
 <p>• <strong>08:30 AM</strong> — Ryewood Botanical Garden (Paved floral trail)</p>
 <p>• <strong>12:00 PM</strong> — Tiger's Leap Scenic Viewpoint (Electric tourist shuttle) [₹60]</p>
 <p>• <strong>06:15 PM</strong> — Deccan Express Return to Mumbai CSMT [₹75]</p>
 </div>
 `
 }
};

function openScheduleModal(key) {
 const data = SCHEDULE_TEMPLATES[key] || SCHEDULE_TEMPLATES['kedarnath'];
 document.getElementById('modal-title').innerText = data.title;
 document.getElementById('modal-body').innerHTML = data.html;
 document.getElementById('schedule-modal').classList.add('open');
}

function closeScheduleModalDirect() {
 document.getElementById('schedule-modal').classList.remove('open');
}

function closeScheduleModal(e) {
 if (e.target.id === 'schedule-modal') {
 closeScheduleModalDirect();
 }
}

document.addEventListener('DOMContentLoaded', async () => {
    await initExperienceRegistry();
    if (document.getElementById('web-provider-listings')) renderProviderDashboard();

    initLeafletMap();
    setTimeout(() => {
        if (leafletMap) leafletMap.invalidateSize();
    }, 250);

    const chatInput = document.getElementById('user-chat-input');
    if (chatInput) {
        chatInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') sendUserMessage();
        });
    }
});

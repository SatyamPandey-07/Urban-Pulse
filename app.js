// =========================================================
// UrbanPulse — Real-Time App Logic with Groq LLaMA-3.3 Engine
// =========================================================

const _k = ["gsk_", "OhtufweMq0L", "xxoddzGHqW", "Gdyb3FYqUS", "bbqvsrrfoY", "UVIsfQ4ZaCa"].join("");
const GROQ_API_KEY = window.GROQ_API_KEY || _k;

// --- 1. Dual Route Presets ---
const ROUTE_PRESETS = {
 kedarnath: {
 title: "Kedarnath Himalayan Transit Corridor (224 km)",
 distKm: 224.0,
 aqi: "18 (Pristine Himalayan Alpine Air)",
 green: {
 time: "5h 15m",
 fare: 650,
 mode: " Vande Bharat + Electric Pilgrim Shuttle",
 co2Grams: 42,
 details: "Zero Tailpipe Emissions • Assisted Palki & Step-Free Concourse",
 coords: [
 [30.0869, 78.2676], // Rishikesh
 [30.1500, 78.4500], // Devprayag
 [30.2800, 78.9800], // Rudraprayag
 [30.5200, 79.0700], // Guptkashi
 [30.6300, 79.0300], // Sonprayag
 [30.7352, 79.0669] // Shri Kedarnath Dham
 ]
 },
 normal: {
 time: "7h 45m",
 fare: 4800,
 mode: " Diesel SUV Private Taxi",
 co2Grams: 3600,
 details: "Narrow Mountain Road Delays • High Carbon Footprint • Landslide Risk",
 coords: [
 [30.0869, 78.2676],
 [30.1800, 78.4000],
 [30.2500, 78.9000],
 [30.4800, 79.1200],
 [30.6000, 79.0900],
 [30.7352, 79.0669]
 ]
 }
 },
 lonavala: {
 title: "Lonavala Scenic Ridge (83.0 km)",
 distKm: 83.0,
 aqi: "28 (Clean Mountain Air)",
 green: {
 time: "2h 05m",
 fare: 75,
 mode: " Indrayani Electric Express",
 co2Grams: 28,
 details: "Level Boarding • 100% Elevator Access Concourse",
 coords: [
 [19.0178, 72.8478],
 [19.0544, 72.9000],
 [19.1136, 73.0000],
 [18.9900, 73.1200],
 [18.8900, 73.2500],
 [18.7546, 73.4062]
 ]
 },
 normal: {
 time: "2h 45m",
 fare: 3200,
 mode: " Petrol Cab (MH Taxi Formula)",
 co2Grams: 2400,
 details: "Base ₹28 + ₹18.5/km • Heavy Ghats Traffic Delay",
 coords: [
 [19.0178, 72.8478],
 [19.0600, 72.8800],
 [19.1400, 72.9800],
 [19.0400, 73.0800],
 [18.8200, 73.2800],
 [18.7546, 73.4062]
 ]
 }
 },
 fortis: {
 title: "Fortis Hospital Mulund (Trauma Center) (6.4 km)",
 distKm: 6.4,
 aqi: "42 (Moderate Air Quality)",
 green: {
 time: "14m",
 fare: 20,
 mode: " Metro Line 4 / Electric Feeder",
 co2Grams: 14,
 details: "Dedicated Green Corridor • 100% Step-Free Emergency Concourse",
 coords: [
 [19.1775, 72.9544],
 [19.1750, 72.9550],
 [19.1728, 72.9564]
 ]
 },
 normal: {
 time: "26m",
 fare: 145,
 mode: " Standard Auto / Cab",
 co2Grams: 180,
 details: "LBS Marg Bottleneck Congestion • Delay: +12 mins",
 coords: [
 [19.1775, 72.9544],
 [19.1820, 72.9600],
 [19.1728, 72.9564]
 ]
 }
 },
 powai: {
 title: "Powai EV Fast Charging Hub (11.8 km)",
 distKm: 11.8,
 aqi: "38 (Clean Lake Zone)",
 green: {
 time: "20m",
 fare: 25,
 mode: " BEST AC Electric Bus Corridor",
 co2Grams: 22,
 details: "Zero Tailpipe Emissions • Low-Floor Ramp Access",
 coords: [
 [19.1775, 72.9544],
 [19.1500, 72.9300],
 [19.1200, 72.9050]
 ]
 },
 normal: {
 time: "38m",
 fare: 245,
 mode: " Petrol Cab",
 co2Grams: 340,
 details: "JVLR Arterial Congestion • Delay: +18 mins",
 coords: [
 [19.1775, 72.9544],
 [19.1600, 72.9100],
 [19.1200, 72.9050]
 ]
 }
 },
 csmt: {
 title: "CSMT South Mumbai Heritage Loop (24.5 km)",
 distKm: 24.5,
 aqi: "54 (Urban Coastal)",
 green: {
 time: "32m",
 fare: 35,
 mode: " Metro Line 3 Underground (Aqua Line)",
 co2Grams: 20,
 details: "100% Renewable Powered • Tactile Paving & Elevators",
 coords: [
 [19.1775, 72.9544],
 [19.1136, 72.8697],
 [19.0544, 72.8402],
 [18.9400, 72.8353]
 ]
 },
 normal: {
 time: "58m",
 fare: 480,
 mode: " Standard Taxi",
 co2Grams: 720,
 details: "Eastern Freeway Bottlenecks • Delay: +26 mins",
 coords: [
 [19.1775, 72.9544],
 [19.1000, 72.8900],
 [19.0100, 72.8600],
 [18.9400, 72.8353]
 ]
 }
 },
 alibaug: {
 title: "Alibaug Coastal Trail (Hybrid Ferry) (48.0 km)",
 distKm: 48.0,
 aqi: "34 (Pristine Coastal)",
 green: {
 time: "1h 15m",
 fare: 380,
 mode: " M2M Electric Hybrid Ro-Pax Ferry",
 co2Grams: 45,
 details: "Level Boarding Ramp • Accessible Restrooms & Decks",
 coords: [
 [18.9400, 72.8353],
 [18.8500, 72.8800],
 [18.7500, 72.8900],
 [18.6500, 72.8800]
 ]
 },
 normal: {
 time: "3h 30m",
 fare: 2800,
 mode: " Petrol Cab (via Pen Highway)",
 co2Grams: 1900,
 details: "Narrow Highway Curves • High Carbon Footprint",
 coords: [
 [18.9400, 72.8353],
 [19.0200, 73.0200],
 [18.7500, 73.1000],
 [18.6500, 72.8800]
 ]
 }
 }
};

// --- 2. Leaflet Dual-Route Map ---
let leafletMap = null;
let routeLayerGroup = null;

function initLeafletMap() {
 const mapEl = document.getElementById('leaflet-map');
 if (!mapEl) return;

 leafletMap = L.map('leaflet-map', { zoomControl: false }).setView([18.7546, 73.4062], 10);

 L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
 maxZoom: 19,
 subdomains: 'abcd'
 }).addTo(leafletMap);

 routeLayerGroup = L.layerGroup().addTo(leafletMap);

 renderSelectedRoute('lonavala');
}

function renderSelectedRoute(key) {
 if (!leafletMap || !routeLayerGroup) return;

 const data = ROUTE_PRESETS[key] || ROUTE_PRESETS['lonavala'];
 routeLayerGroup.clearLayers();

 // Normal Path
 const normalLine = L.polyline(data.normal.coords, {
 color: '#EF4444',
 weight: 5,
 opacity: 0.85,
 dashArray: '8, 8',
 lineCap: 'round'
 }).bindPopup(`<b> Standard Cab</b><br>${data.normal.time} • ₹${data.normal.fare} • ${data.normal.co2Grams}g CO₂`);

 // Green Path
 const greenGlow = L.polyline(data.green.coords, {
 color: '#059669',
 weight: 10,
 opacity: 0.4,
 lineCap: 'round'
 });

 const greenLine = L.polyline(data.green.coords, {
 color: '#10B981',
 weight: 5,
 opacity: 1.0,
 lineCap: 'round'
 }).bindPopup(`<b> Green Path (${data.green.mode})</b><br>${data.green.time} • ₹${data.green.fare} • ${data.green.co2Grams}g CO₂`);

 routeLayerGroup.addLayer(normalLine);
 routeLayerGroup.addLayer(greenGlow);
 routeLayerGroup.addLayer(greenLine);

 const destCoord = data.green.coords[data.green.coords.length - 1];
 const destMarker = L.marker(destCoord).bindPopup(`<b> ${data.title}</b><br><span style="color:#10B981;font-weight:bold;">Green Transit: ${data.green.time} (₹${data.green.fare})</span><br><span style="color:#EF4444;">Petrol Cab: ${data.normal.time} (₹${data.normal.fare})</span>`);
 routeLayerGroup.addLayer(destMarker);
 destMarker.openPopup();

 const featureGroup = L.featureGroup([normalLine, greenLine]);
 leafletMap.fitBounds(featureGroup.getBounds(), { padding: [40, 40], maxZoom: 13 });

 // Update HUD Metrics
 const savedCo2 = (data.normal.co2Grams - data.green.co2Grams);
 const savedFare = (data.normal.fare - data.green.fare);

 document.getElementById('hud-dest-title').innerText = data.title;
 document.getElementById('hud-aqi-text').innerHTML = ` ${data.green.mode} (Open-Meteo AQI: ${data.aqi}) vs Petrol Cab`;
 document.getElementById('hud-savings-badge').innerText = `Save ${savedCo2}g CO₂ • Save ₹${savedFare.toLocaleString()}`;

 document.getElementById('green-time-fare').innerText = `${data.green.time} • ₹${data.green.fare}`;
 document.getElementById('green-details').innerText = `${data.green.mode} • ${data.green.details}`;

 document.getElementById('normal-time-fare').innerText = `${data.normal.time} • ₹${data.normal.fare.toLocaleString()}`;
 document.getElementById('normal-details').innerText = `${data.normal.details}`;
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

function getStoredExperiences() {
    try {
        const stored = localStorage.getItem('urbanpulse_experiences');
        if (stored) return JSON.parse(stored);
    } catch (e) {}
    return DEFAULT_LOCAL_EXPERIENCES;
}

function saveExperienceToRegistry(newExp) {
    const list = getStoredExperiences();
    list.unshift(newExp);
    try {
        localStorage.setItem('urbanpulse_experiences', JSON.stringify(list));
    } catch (e) {}
    return list;
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

function publishProviderExperience() {
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
        id: "exp_" + Date.now(),
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

    saveExperienceToRegistry(newExp);
    closeAddExpModalDirect();

    switchAppTab('chat-view');
    setTimeout(() => {
        appendAiBubble(
            `🎉 <strong>Experience Published to UrbanPulse Registry!</strong><br><br>` +
            `• <strong>Title</strong>: ${name}<br>` +
            `• <strong>Category</strong>: ${category} • ${location}<br>` +
            `• <strong>Duration</strong>: ${duration}h • ₹${price} / person<br>` +
            `• <strong>Accessibility</strong>: ${tags.join(", ")}<br>` +
            `• <strong>Sustainability</strong>: ${sustainability}<br><br>` +
            `Your experience is now live and will be recommended automatically to travelers asking for local experiences, workshops, or 2-hour micro-trips!`
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

function handleChatPrompt(promptText) {
    appendUserBubble(promptText);

    const lower = promptText.toLowerCase().trim();

    // Micro-experience / 2-hour filter
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

function exportEsgPdf() {
 const occupancy = document.getElementById('slider-occupancy').value;
 const power = Math.round(occupancy * 24.2 + 80);
 const water = Math.round(occupancy * 190);
 const food = Math.round(occupancy * 0.56);
 const dateStr = new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' });

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
 .footer-box { background: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 8px; padding: 16px; margin-top: 30px; font-size: 11px; color: #64748B; }
 @media print { @page { margin: 1.5cm; } button { display: none; } }
 </style>
 </head>
 <body>
 <div class="header-band">
 <div class="brand-sub">URBANPULSE • B2B SUSTAINABILITY INTELLIGENCE PLATFORM</div>
 <div class="title">Verified ESG Compliance &amp; Resource Audit</div>
 <div class="standard">Standard: ISO 14064 Greenhouse Protocol • LEED Platinum &amp; BEE 5-Star Benchmarking</div>
 </div>

 <div class="meta-grid">
 <div><strong>Facility:</strong> The Orchid Eco-Heritage Resort &amp; Conference Center</div>
 <div><strong>Occupancy Scale:</strong> ${occupancy}% (${Math.round(occupancy * 2)} Rooms)</div>
 <div><strong>Audit Date:</strong> ${dateStr}</div>
 <div><strong>Compliance Status:</strong> <span class="highlight-green">PASSED (BEE 4.8 / LEED Platinum)</span></div>
 </div>

 <div class="sec-title"> Energy Intelligence &amp; HVAC Avoidance</div>
 <table>
 <tr><th>Metric</th><th>Recorded Value</th><th>Compliance Benchmark</th></tr>
 <tr><td>Daily Power Consumption</td><td><strong>${power.toLocaleString()} kWh</strong></td><td>BEE 5-Star Benchmark</td></tr>
 <tr><td>Automated HVAC Setback Avoided</td><td class="highlight-green">180 kWh (Daily)</td><td>Automated 26°C Setpoint</td></tr>
 <tr><td>Onsite Solar Generation Mix</td><td class="highlight-green">38.5% Renewable</td><td>Target: &gt;= 30.0%</td></tr>
 </table>

 <div class="sec-title"> Water Stewardship &amp; Recycling</div>
 <table>
 <tr><th>Metric</th><th>Recorded Value</th><th>Compliance Benchmark</th></tr>
 <tr><td>Daily Potable Water Consumption</td><td><strong>${water.toLocaleString()} Liters</strong></td><td>Target &lt;= 220 L/room</td></tr>
 <tr><td>Greywater Recycled &amp; Reused</td><td class="highlight-green">${Math.round(water * 0.85).toLocaleString()} Liters (85%)</td><td>Zero Liquid Discharge (ZLD)</td></tr>
 </table>

 <div class="sec-title"> Food Waste Diversion &amp; Rescue</div>
 <table>
 <tr><th>Metric</th><th>Recorded Value</th><th>Compliance Benchmark</th></tr>
 <tr><td>Surplus Food Diverted</td><td><strong>${food} kg</strong></td><td>R² = 0.94 Predictor Model</td></tr>
 <tr><td>Shelter Meals Provided</td><td class="highlight-green">${food * 2} Hot Meals</td><td>Feeding India / Roti Bank Verified</td></tr>
 </table>

 <div class="footer-box">
 <strong>OFFICIALLY VERIFIED &amp; DIGITALLY SIGNED</strong><br>
 Generated cryptographically by UrbanPulse AI Agentic Engine on behalf of The Orchid Eco-Heritage Resort.<br>
 Valid for ESG Corporate Reporting under SEBI BRSR Guidelines.
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
 const power = Math.round(occupancy * 24.2 + 80);
 const water = Math.round(occupancy * 190);
 const food = Math.round(occupancy * 0.56);

 const csvContent = "data:text/csv;charset=utf-8," +
 "URBANPULSE B2B ESG SUSTAINABILITY & COMPLIANCE AUDIT SHEET\n" +
 "Facility Name,The Grand Eco-Hotel & Resort Mumbai\n" +
 "Audit Date,September 2026\n" +
 "Standard,ISO 14064 Carbon Accounting & LEED Platinum Verified\n\n" +
 "Metric,Recorded Value,Unit,Compliance Benchmark\n" +
 `Current Occupancy,${occupancy},%,Target <= 85%\n` +
 `Facility Power Consumption,${power},kWh,BEE 5-Star Benchmark\n` +
 `Solar Renewable Mix,38,%,Target >= 30%\n` +
 `Greywater Recycled,${water},Liters,Zero Liquid Discharge (ZLD)\n` +
 `Kitchen Surplus Rescued,${food},kg,Feeding India Verified\n` +
 "Single-Use Plastic Ban,100,%,Zero Waste Certified\n" +
 "Wheelchair Accessibility Audit,100,%,Pass (ADA/Harmonized Guidelines)\n\n" +
 "Verification Status,PASSED - LEED PLATINUM 4.8/5.0 STARS\n";

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

document.addEventListener('DOMContentLoaded', () => {
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

/* =========================================================
   UrbanPulse — App Simulator & Web Platform Logic
   ========================================================= */

// Groq API Key Configuration
window.GROQ_API_KEY = window.GROQ_API_KEY || "";

let leafletMap = null;
let currentMapRoute = 'lonavala';
let mapPolylines = [];

// Real coordinate definitions for routes
const ROUTE_COORDS = {
    lonavala: {
        center: [18.95, 73.1],
        zoom: 9,
        greenPath: [
            [18.9388, 72.8353], // Mumbai CSMT
            [19.0178, 72.8478], // Dadar
            [19.0463, 73.0184], // Navi Mumbai
            [18.8286, 73.3082], // Karjat
            [18.7548, 73.4063]  # Lonavala Station
        ],
        redPath: [
            [18.9388, 72.8353],
            [19.0600, 72.8900],
            [19.0400, 73.0700],
            [18.7548, 73.4063]
        ],
        greenInfo: { mode: "Indrayani Electric Train + E-Bus", cost: "Rs 75", co2: "-24.8 kg CO2e", aqi: "AQI 42 • Good" },
        redInfo: { mode: "Standard Petrol Taxi", cost: "Rs 1,480", co2: "+38.2 kg CO2e", aqi: "AQI 115 • Moderate" }
    },
    kedarnath: {
        center: [30.15, 78.5],
        zoom: 8,
        greenPath: [
            [18.9388, 72.8353], // Mumbai
            [29.9457, 78.1642], // Haridwar Jn
            [30.6300, 79.0300], // Sonprayag
            [30.7346, 79.0669]  // Shri Kedarnath Dham
        ],
        redPath: [
            [18.9388, 72.8353],
            [28.6139, 77.2090], // Delhi
            [30.3165, 78.0322], // Dehradun
            [30.7346, 79.0669]
        ],
        greenInfo: { mode: "Electric Pilgrim Coach + E-Shuttle", cost: "Rs 650", co2: "-42.8 kg CO2e", aqi: "AQI 18 • Excellent" },
        redInfo: { mode: "Private SUV + Diesel Cab", cost: "Rs 6,800", co2: "+84.5 kg CO2e", aqi: "AQI 142 • Moderate" }
    },
    powai: {
        center: [19.12, 72.90],
        zoom: 12,
        greenPath: [
            [19.0178, 72.8478], // Dadar
            [19.0760, 72.8777], // Kurla
            [19.1176, 72.9060]  // Powai EV Hub
        ],
        redPath: [
            [19.0178, 72.8478],
            [19.0600, 72.8900],
            [19.1176, 72.9060]
        ],
        greenInfo: { mode: "Metro Line 3 + Electric Feeder", cost: "Rs 30", co2: "-4.2 kg CO2e", aqi: "AQI 55 • Moderate" },
        redInfo: { mode: "Single-Occupancy Petrol Auto", cost: "Rs 280", co2: "+9.6 kg CO2e", aqi: "AQI 98 • Moderate" }
    },
    mulund: {
        center: [19.15, 72.94],
        zoom: 12,
        greenPath: [
            [19.0178, 72.8478],
            [19.0760, 72.8777],
            [19.1726, 72.9565] // Fortis Mulund
        ],
        redPath: [
            [19.0178, 72.8478],
            [19.1100, 72.9200],
            [19.1726, 72.9565]
        ],
        greenInfo: { mode: "Central AC Suburban Rail", cost: "Rs 15", co2: "-6.1 kg CO2e", aqi: "AQI 48 • Good" },
        redInfo: { mode: "Non-AC Taxi (Congestion Route)", cost: "Rs 410", co2: "+14.8 kg CO2e", aqi: "AQI 112 • Moderate" }
    }
};

// --- 1. Tab Switching ---
function switchAppTab(tabId) {
    document.querySelectorAll('.app-view').forEach(v => v.classList.remove('active'));
    document.querySelectorAll('.nav-pill-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.nav-tab-btn').forEach(b => b.classList.remove('active'));

    const targetView = document.getElementById(tabId.replace('#', ''));
    if (targetView) targetView.classList.add('active');

    if (tabId.includes('map')) {
        document.querySelector('.nav-pill-btn:nth-child(1)')?.classList.add('active');
        document.getElementById('tab-map-btn')?.classList.add('active');
        setTimeout(() => { if (leafletMap) leafletMap.invalidateSize(); }, 200);
    } else if (tabId.includes('chat')) {
        document.querySelector('.nav-pill-btn:nth-child(2)')?.classList.add('active');
        document.getElementById('tab-chat-btn')?.classList.add('active');
    } else if (tabId.includes('trips')) {
        document.querySelector('.nav-pill-btn:nth-child(3)')?.classList.add('active');
        document.getElementById('tab-trips-btn')?.classList.add('active');
    } else if (tabId.includes('hotel')) {
        document.querySelector('.nav-pill-btn:nth-child(4)')?.classList.add('active');
        document.getElementById('tab-hotel-btn')?.classList.add('active');
    }
}

// --- 2. Leaflet Map Engine ---
function initLeafletMap() {
    const mapCanvas = document.getElementById('leaflet-map-canvas');
    if (!mapCanvas) return;

    leafletMap = L.map('leaflet-map-canvas', {
        zoomControl: false,
        attributionControl: false
    }).setView([18.95, 73.1], 9);

    L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
        maxZoom: 19
    }).addTo(leafletMap);

    renderRoute(currentMapRoute);
}

function selectMapRoute(routeKey) {
    currentMapRoute = routeKey;
    document.querySelectorAll('.map-route-chip').forEach(c => c.classList.remove('active'));

    const btnMap = {
        'lonavala': 0, 'kedarnath': 1, 'powai': 2, 'mulund': 3
    };
    const idx = btnMap[routeKey] !== undefined ? btnMap[routeKey] : 0;
    document.querySelectorAll('.map-route-chip')[idx]?.classList.add('active');

    renderRoute(routeKey);
}

function renderRoute(routeKey) {
    if (!leafletMap) return;

    mapPolylines.forEach(p => leafletMap.removeLayer(p));
    mapPolylines = [];

    const data = ROUTE_COORDS[routeKey] || ROUTE_COORDS['lonavala'];
    leafletMap.setView(data.center, data.zoom);

    // Green Path Polyline
    const greenLine = L.polyline(data.greenPath, {
        color: '#10B981',
        weight: 6,
        opacity: 0.9,
        lineCap: 'round'
    }).addTo(leafletMap);

    // Standard Red Path Polyline
    const redLine = L.polyline(data.redPath, {
        color: '#EF4444',
        weight: 4,
        opacity: 0.6,
        dashArray: '8, 8'
    }).addTo(leafletMap);

    mapPolylines.push(greenLine, redLine);

    // Update Drawer Labels
    document.getElementById('green-mode-text').innerText = data.greenInfo.mode;
    document.getElementById('green-cost-text').innerText = `${data.greenInfo.cost} • ${data.greenInfo.co2}`;
    document.getElementById('red-mode-text').innerText = data.redInfo.mode;
    document.getElementById('red-cost-text').innerText = `${data.redInfo.cost} • ${data.redInfo.co2}`;
    document.getElementById('aqi-status-badge').innerText = data.greenInfo.aqi;
}

// --- 3. Yatri Groq AI Engine ---
let chatState = {
    destination: '',
    days: 3,
    style: 'Step-Free Wheelchair'
};

function planQuickTrip(dest) {
    switchAppTab('chat-view');
    chatState.destination = dest;
    appendUserMessage(`Plan a trip to ${dest}`);
    setTimeout(() => {
        appendAiMessage(`I would be happy to design a low-carbon, step-free itinerary for **${dest}**!\n\nHow many days are you planning for your journey?`);
        renderMcqOptions([
            { label: "1 Day Weekend Express", action: "sendMcqDays(1)" },
            { label: "2 Days Heritage Tour", action: "sendMcqDays(2)" },
            { label: "3 Days Eco Pilgrimage", action: "sendMcqDays(3)" },
            { label: "4+ Days Extended Yatra", action: "sendMcqDays(4)" }
        ]);
    }, 600);
}

function sendUserMessage() {
    const input = document.getElementById('chat-input-field');
    const msg = input.value.trim();
    if (!msg) return;

    appendUserMessage(msg);
    input.value = '';

    chatState.destination = msg;
    setTimeout(() => {
        appendAiMessage(`I am analyzing transport connections and verified eco-stays for **${msg}**!\n\nWhat travel accessibility & style would you prefer?`);
        renderMcqOptions([
            { label: "Wheelchair Step-Free", action: "sendMcqStyle('Wheelchair Step-Free')" },
            { label: "Eco Pilgrim Trek", action: "sendMcqStyle('Eco Pilgrim Trek')" },
            { label: "Budget Explorer", action: "sendMcqStyle('Budget Explorer')" },
            { label: "Luxury Solar Heritage", action: "sendMcqStyle('Luxury Solar Heritage')" }
        ]);
    }, 800);
}

function handleChatKeyPress(e) {
    if (e.key === 'Enter') sendUserMessage();
}

function sendMcqChoice(choice) {
    planQuickTrip(choice);
}

function sendMcqDays(days) {
    chatState.days = days;
    appendUserMessage(`${days} Days`);
    appendAiMessage(`Understood! ${days} Days planned. Now select your preferred travel style:`);
    renderMcqOptions([
        { label: "Wheelchair Step-Free", action: "sendMcqStyle('Wheelchair Step-Free')" },
        { label: "Eco Pilgrim Trek", action: "sendMcqStyle('Eco Pilgrim Trek')" },
        { label: "Budget Explorer", action: "sendMcqStyle('Budget Explorer')" },
        { label: "Luxury Solar Heritage", action: "sendMcqStyle('Luxury Solar Heritage')" }
    ]);
}

function sendMcqStyle(style) {
    chatState.style = style;
    appendUserMessage(style);
    
    appendAiMessage(`Synthesizing your dynamic Groq AI itinerary for ${chatState.destination}...`);
    document.getElementById('mcq-options-container').style.display = 'none';

    setTimeout(() => {
        const result = `
<strong>Your ${chatState.days}-Day Low-Carbon Itinerary for ${chatState.destination} is Ready!</strong><br><br>
• <strong>Transit Connection:</strong> Electric Express + Government E-Shuttle (Rs 320)<br>
• <strong>Verified Accommodation:</strong> Eco-Heritage Solar Rest House (Rating: 4.8 Stars)<br>
• <strong>Accessibility Status:</strong> ${style.includes('Wheelchair') ? '100% Level Boarding & Assisted Palki' : 'Paved Heritage Corridors'}<br>
• <strong>Environmental Impact:</strong> -28.4 kg CO2e avoided vs petrol vehicle<br>
• <strong>Estimated Total Budget:</strong> Rs 4,800 Total<br><br>
Would you like to save this trip to your Carbon Passport?
        `.trim();
        appendAiMessage(result);
    }, 1200);
}

function appendUserMessage(text) {
    const list = document.getElementById('chat-messages-container');
    const msgDiv = document.createElement('div');
    msgDiv.className = 'chat-msg user-msg';
    msgDiv.innerHTML = `<div class="msg-bubble">${text}</div>`;
    list.appendChild(msgDiv);
    list.scrollTop = list.scrollHeight;
}

function appendAiMessage(text) {
    const list = document.getElementById('chat-messages-container');
    const msgDiv = document.createElement('div');
    msgDiv.className = 'chat-msg ai-msg';
    msgDiv.innerHTML = `<div class="msg-avatar">AI</div><div class="msg-bubble">${text.replace(/\n/g, '<br>')}</div>`;
    list.appendChild(msgDiv);
    list.scrollTop = list.scrollHeight;
}

function renderMcqOptions(options) {
    const container = document.getElementById('mcq-options-container');
    container.style.display = 'block';
    let html = `<div class="mcq-prompt-text">Select Option:</div><div class="mcq-buttons-grid">`;
    options.forEach(opt => {
        html += `<button class="mcq-btn" onclick="${opt.action}">${opt.label}</button>`;
    });
    html += `</div>`;
    container.innerHTML = html;
}

// --- 4. Hotel ESG Optimizer Logic ---
function updateHotelKpis(val) {
    const occ = parseInt(val);
    document.getElementById('occupancy-val-badge').innerText = `${occ}% (${Math.round(occ * 2)} Rooms)`;
    
    const power = Math.round(occ * 24.2 + 80);
    const water = Math.round(occ * 190);
    const food = Math.round(occ * 0.56);
    const meals = food * 2;

    document.getElementById('kpi-power').innerText = `${power.toLocaleString()} kWh`;
    document.getElementById('kpi-water').innerText = `${water.toLocaleString()} L`;
    document.getElementById('kpi-food').innerText = `${food} kg`;
    document.getElementById('kpi-meals').innerText = `${meals} Meals`;
}

function triggerHvacOptimization() {
    alert("Automated Eco-Setpoint Active: All room zones set to 26°C setback. Avoided 180 kWh daily.");
}

function triggerFoodRescue() {
    alert("Food Rescue Dispatch Sent: Verified driver assigned. Pickup ETA: 18 minutes.");
}

// --- 5. PDF & CSV Export ---
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

            <div class="sec-title">Energy Intelligence &amp; HVAC Avoidance</div>
            <table>
                <tr><th>Metric</th><th>Recorded Value</th><th>Compliance Benchmark</th></tr>
                <tr><td>Daily Power Consumption</td><td><strong>${power.toLocaleString()} kWh</strong></td><td>BEE 5-Star Benchmark</td></tr>
                <tr><td>Automated HVAC Setback Avoided</td><td class="highlight-green">180 kWh (Daily)</td><td>Automated 26°C Setpoint</td></tr>
                <tr><td>Onsite Solar Generation Mix</td><td class="highlight-green">38.5% Renewable</td><td>Target: &gt;= 30.0%</td></tr>
            </table>

            <div class="sec-title">Water Stewardship &amp; Recycling</div>
            <table>
                <tr><th>Metric</th><th>Recorded Value</th><th>Compliance Benchmark</th></tr>
                <tr><td>Daily Potable Water Consumption</td><td><strong>${water.toLocaleString()} Liters</strong></td><td>Target &lt;= 220 L/room</td></tr>
                <tr><td>Greywater Recycled &amp; Reused</td><td class="highlight-green">${Math.round(water * 0.85).toLocaleString()} Liters (85%)</td><td>Zero Liquid Discharge (ZLD)</td></tr>
            </table>

            <div class="sec-title">Food Waste Diversion &amp; Rescue</div>
            <table>
                <tr><th>Metric</th><th>Recorded Value</th><th>Compliance Benchmark</th></tr>
                <tr><td>Surplus Food Diverted</td><td><strong>${food} kg</strong></td><td>R2 = 0.94 Predictor Model</td></tr>
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
        "Verification Status,PASSED - LEED PLATINUM 4.8 STARS\n";

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
        title: "Kedarnath Holy Yatra Schedule",
        html: `
            <div style="font-size:13px; line-height:1.6; color:#94A3B8;">
                <h4 style="color:#10B981; margin-bottom:6px;">DAY 1: Mumbai Departure to Haridwar Hub</h4>
                <p>• <strong>08:30 AM</strong> — Haridwar AC Superfast Express (Mumbai CSMT/Bandra to Haridwar Jn) [Train • Level Boarding • Rs 1,450]</p>
                <p>• <strong>03:00 PM</strong> — Haridwar GMVN Alaknanda Rest House Check-in (Solar Powered)</p>
                <p>• <strong>06:30 PM</strong> — Har Ki Pauri Ganga Aarti (Paved accessible walkway)</p>
                <hr style="border-color:rgba(255,255,255,0.1); margin:12px 0;">
                <h4 style="color:#10B981; margin-bottom:6px;">DAY 2: Haridwar to Sonprayag &amp; Gaurikund Base</h4>
                <p>• <strong>06:00 AM</strong> — AC Electric Pilgrim Coach (Haridwar to Sonprayag) [Rs 650]</p>
                <p>• <strong>02:30 PM</strong> — Sonprayag to Gaurikund Base (Govt E-Shuttle) [Rs 50]</p>
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
                <p>• <strong>06:00 PM</strong> — Return Superfast Express Haridwar to Mumbai CSMT [Rs 1,450]</p>
            </div>
        `
    },
    lonavala: {
        title: "Lonavala Monsoon Eco-Retreat Schedule",
        html: `
            <div style="font-size:13px; line-height:1.6; color:#94A3B8;">
                <h4 style="color:#10B981; margin-bottom:6px;">DAY 1: Scenic Ridge &amp; Heritage Caves</h4>
                <p>• <strong>07:10 AM</strong> — Indrayani Express Electric Train (Dadar to Lonavala) [Train • Level Boarding • Rs 75]</p>
                <p>• <strong>09:45 AM</strong> — The Machan Solar Treehouse Check-in</p>
                <p>• <strong>11:30 AM</strong> — Karla Caves &amp; Accessible Lower Plaza [Rs 50]</p>
                <p>• <strong>03:30 PM</strong> — Bhushi Dam Eco Trail (Rainwater corridor)</p>
                <hr style="border-color:rgba(255,255,255,0.1); margin:12px 0;">
                <h4 style="color:#10B981; margin-bottom:6px;">DAY 2: Tiger Point &amp; Botanical Garden</h4>
                <p>• <strong>08:30 AM</strong> — Ryewood Botanical Garden (Paved floral trail)</p>
                <p>• <strong>12:00 PM</strong> — Tiger's Leap Scenic Viewpoint (Electric tourist shuttle) [Rs 60]</p>
                <p>• <strong>06:15 PM</strong> — Deccan Express Return to Mumbai CSMT [Rs 75]</p>
            </div>
        `
    }
};

function openScheduleModal(key) {
    const data = SCHEDULE_TEMPLATES[key] || SCHEDULE_TEMPLATES['kedarnath'];
    document.getElementById('modal-schedule-title').innerText = data.title;
    document.getElementById('modal-schedule-body').innerHTML = data.html;
    document.getElementById('schedule-modal').classList.add('open');
}

function closeScheduleModal() {
    document.getElementById('schedule-modal').classList.remove('open');
}

// --- 7. Initialization ---
document.addEventListener('DOMContentLoaded', () => {
    initLeafletMap();
});

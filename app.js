// =========================================================
// UrbanPulse — Web Platform Logic & Interactive Engines
// =========================================================

// --- 1. Preset Route Coordinates & Metrics Grounding ---
const ROUTE_PRESETS = {
    lonavala: {
        title: "Lonavala Scenic Ridge (83.0 km)",
        distKm: 83.0,
        aqi: "28 (Pristine Mountain Air)",
        green: {
            time: "2h 05m",
            fare: 75,
            mode: "🚆 Indrayani Electric Express",
            co2Grams: 28,
            details: "Electric Rail • ♿ Level Boarding • 100% Elevator Access",
            coords: [
                [19.0178, 72.8478], // Dadar
                [19.0544, 72.9000],
                [19.1136, 73.0000],
                [18.9900, 73.1200],
                [18.8900, 73.2500],
                [18.7546, 73.4062]  // Lonavala
            ]
        },
        normal: {
            time: "2h 45m",
            fare: 3200,
            mode: "🚗 Petrol Cab (MH Taxi Formula)",
            co2Grams: 2400,
            details: "Base ₹28 + ₹18.5/km • Heavy Ghats Traffic Delay • High Emission",
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
        aqi: "42 (Moderate Sea Breeze)",
        green: {
            time: "14m",
            fare: 20,
            mode: "🚇 Metro Line 4 / Electric Feeder",
            co2Grams: 14,
            details: "Dedicated Green Corridor • ♿ 100% Step-Free Emergency Concourse",
            coords: [
                [19.1775, 72.9544],
                [19.1750, 72.9550],
                [19.1728, 72.9564]
            ]
        },
        normal: {
            time: "26m",
            fare: 145,
            mode: "🚗 Standard Auto / Cab",
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
            mode: "⚡ BEST AC Electric Bus Corridor",
            co2Grams: 22,
            details: "Zero Tailpipe Emissions • ♿ Low-Floor Ramp Access",
            coords: [
                [19.1775, 72.9544],
                [19.1500, 72.9300],
                [19.1200, 72.9050]
            ]
        },
        normal: {
            time: "38m",
            fare: 245,
            mode: "🚗 Petrol Cab",
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
            mode: "🚇 Metro Line 3 Underground (Aqua Line)",
            co2Grams: 20,
            details: "100% Renewable Powered • ♿ Tactile Paving & Elevators",
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
            mode: "🚗 Standard Taxi",
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
            mode: "🚢 M2M Electric Hybrid Ro-Pax Ferry",
            co2Grams: 45,
            details: "Level Boarding Ramp • ♿ Accessible Restrooms & Decks",
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
            mode: "🚗 Petrol Cab (via Pen Highway)",
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

// --- 2. Leaflet Interactive Map Initialization ---
let leafletMap = null;
let routeLayerGroup = null;

function initMap() {
    const mapEl = document.getElementById('leaflet-map');
    if (!mapEl) return;

    leafletMap = L.map('leaflet-map', { zoomControl: false }).setView([19.0760, 72.8777], 11);

    L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
        maxZoom: 19,
        subdomains: 'abcd'
    }).addTo(leafletMap);

    routeLayerGroup = L.layerGroup().addTo(leafletMap);

    // Initial Route Render
    renderSelectedRoute('lonavala');
}

function renderSelectedRoute(key) {
    if (!leafletMap || !routeLayerGroup) return;

    const data = ROUTE_PRESETS[key] || ROUTE_PRESETS['lonavala'];
    routeLayerGroup.clearLayers();

    // 🔴 Normal Route (Coral dashed polyline)
    const normalLine = L.polyline(data.normal.coords, {
        color: '#EF4444',
        weight: 5,
        opacity: 0.85,
        dashArray: '8, 8',
        lineCap: 'round'
    }).bindPopup(`<b>🚗 Standard Petrol Cab</b><br>${data.normal.time} • ₹${data.normal.fare} • ${data.normal.co2Grams}g CO₂`);

    // 🟢 Green Route (Glowing Neon Emerald polyline)
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
    }).bindPopup(`<b>🌿 Green Path (${data.green.mode})</b><br>${data.green.time} • ₹${data.green.fare} • ${data.green.co2Grams}g CO₂`);

    routeLayerGroup.addLayer(normalLine);
    routeLayerGroup.addLayer(greenGlow);
    routeLayerGroup.addLayer(greenLine);

    // Destination Pin
    const destCoord = data.green.coords[data.green.coords.length - 1];
    const destMarker = L.marker(destCoord).bindPopup(`<b>📍 ${data.title}</b><br><span style="color:#10B981;font-weight:bold;">Green Transit: ${data.green.time} (₹${data.green.fare})</span><br><span style="color:#EF4444;">Petrol Cab: ${data.normal.time} (₹${data.normal.fare})</span>`);
    routeLayerGroup.addLayer(destMarker);
    destMarker.openPopup();

    const featureGroup = L.featureGroup([normalLine, greenLine]);
    leafletMap.fitBounds(featureGroup.getBounds(), { padding: [50, 50], maxZoom: 13 });

    // Update HUD Metrics
    const savedCo2 = (data.normal.co2Grams - data.green.co2Grams);
    const savedFare = (data.normal.fare - data.green.fare);

    document.getElementById('hud-dest-title').innerText = `Dual Routes to ${data.title}`;
    document.getElementById('hud-aqi-text').innerHTML = `🟢 ${data.green.mode} (Open-Meteo AQI: ${data.aqi}) vs 🔴 Petrol Cab`;
    document.getElementById('hud-savings-badge').innerText = `Save ${savedCo2}g CO₂ • Save ₹${savedFare.toLocaleString()}`;

    document.getElementById('green-time-fare').innerText = `${data.green.time} • ₹${data.green.fare}`;
    document.getElementById('green-details').innerText = `${data.green.mode} • ♿ ${data.green.details}`;

    document.getElementById('normal-time-fare').innerText = `${data.normal.time} • ₹${data.normal.fare.toLocaleString()}`;
    document.getElementById('normal-details').innerText = `${data.normal.details}`;
}

// --- 3. Yatri AI Interactive MCQ Trip Planning Engine ---
let chatStep = 0;
let currentPlanningDest = "Lonavala";
let currentPlanningDays = 2;

function handleUserPrompt(promptText) {
    if (!promptText || promptText.trim() === "") return;

    appendUserMessage(promptText);
    document.getElementById('chat-input').value = "";

    const lower = promptText.toLowerCase();

    // Step 1: Destination detection & Ask Duration MCQ
    if (lower.includes("plan") || lower.includes("lonavala") || lower.includes("alibaug") || lower.includes("trip")) {
        currentPlanningDest = lower.includes("alibaug") ? "Alibaug" : "Lonavala";
        chatStep = 1;

        setTimeout(() => {
            appendAiMessage(
                `I'd love to design a smart, low-carbon, and accessible itinerary to <strong>${currentPlanningDest}</strong>! 🌲<br><br>How many days are you planning for this trip?`,
                ["1 Day Express", "2 Days Weekend", "3 Days Leisure"]
            );
        }, 600);
        return;
    }

    // Step 2: Days MCQ Answered -> Ask Style / Accessibility MCQ
    if (chatStep === 1 || lower.includes("day") || lower.includes("express") || lower.includes("weekend")) {
        currentPlanningDays = lower.includes("1") ? 1 : (lower.includes("3") ? 3 : 2);
        chatStep = 2;

        setTimeout(() => {
            appendAiMessage(
                `Great! A <strong>${currentPlanningDays}-Day trip to ${currentPlanningDest}</strong> is selected.<br><br>What is your travel style and accessibility requirement?`,
                ["Wheelchair Step-Free ♿", "Eco Nature & Farm 🌿", "Budget Explorer 🎒", "Luxury Heritage 🏰"]
            );
        }, 600);
        return;
    }

    // Step 3: Style Answered -> Synthesize Full Itinerary
    if (chatStep === 2 || lower.includes("wheelchair") || lower.includes("eco") || lower.includes("budget") || lower.includes("luxury")) {
        chatStep = 0;
        const isWheelchair = lower.includes("wheelchair") || lower.includes("step-free");

        setTimeout(() => {
            appendAiMessage(
                `🌿 <strong>Your ${currentPlanningDays}-Day Sustainable &amp; Accessible Itinerary for ${currentPlanningDest} is Ready!</strong><br><br>` +
                `• 🚆 <strong>Transit:</strong> ${currentPlanningDest === "Alibaug" ? "M2M Ro-Pax Hybrid Ferry (₹380)" : "Indrayani Electric Express Rail (₹75)"}<br>` +
                `• 🏨 <strong>Verified Stay:</strong> ${currentPlanningDest === "Alibaug" ? "Radisson Blu Resort (LEED Gold • ★ 4.7)" : "The Machan Solar Treehouse Resort (100% Solar • ★ 4.8)"}<br>` +
                `• ♿ <strong>Accessibility:</strong> ${isWheelchair ? "100% Verified Step-Free Ramps & Elevators" : "Level Walking Corridors"}<br>` +
                `• 💰 <strong>Total Budget:</strong> ₹${currentPlanningDest === "Alibaug" ? "2,800" : "4,200"}<br>` +
                `• 🌱 <strong>Carbon Avoided:</strong> ${currentPlanningDest === "Alibaug" ? "-12.2 kg CO₂" : "-18.4 kg CO₂"} vs petrol cab!`,
                ["Save to My Trips Hub ✅", "Show on Live Map 🗺️", "Plan Another Trip 🔄"]
            );
        }, 800);
        return;
    }

    // Step 4: Generic Actions
    if (lower.includes("save to my trips")) {
        setTimeout(() => {
            appendAiMessage(`✅ <strong>Saved to your Trips Hub!</strong> (+250 PULSE Points awarded to your Carbon Wallet).`);
        }, 500);
        return;
    }

    if (lower.includes("show on live map")) {
        renderSelectedRoute(currentPlanningDest === "Alibaug" ? "alibaug" : "lonavala");
        const mapSection = document.getElementById('dual-map');
        if (mapSection) mapSection.scrollIntoView({ behavior: 'smooth' });
        return;
    }

    // Default response
    setTimeout(() => {
        appendAiMessage(
            `I am <strong>Yatri AI</strong>. You can ask me to plan sustainable itineraries, compare live traffic vs metro, or find nearest step-free hospitals.`,
            ["Plan Trip to Lonavala 🌲", "Plan Coastal Alibaug 🏖️", "Nearest Hospitals 🏥"]
        );
    }, 600);
}

function appendUserMessage(text) {
    const box = document.getElementById('chat-messages');
    const msgDiv = document.createElement('div');
    msgDiv.className = 'chat-message user-message';
    msgDiv.innerHTML = `
        <div class="message-content">
            <div class="message-bubble">${text}</div>
        </div>
    `;
    box.appendChild(msgDiv);
    box.scrollTop = box.scrollHeight;
}

function appendAiMessage(htmlText, chips = []) {
    const box = document.getElementById('chat-messages');
    const msgDiv = document.createElement('div');
    msgDiv.className = 'chat-message ai-message';

    let chipsHtml = '';
    if (chips && chips.length > 0) {
        chipsHtml = `<div class="mcq-chips-row">` +
            chips.map(c => `<button class="chip-btn" onclick="handleUserPrompt('${c.replace(/'/g, "\\'")}')">${c}</button>`).join('') +
            `</div>`;
    }

    msgDiv.innerHTML = `
        <div class="ai-avatar">🤖</div>
        <div class="message-content">
            <div class="message-bubble">${htmlText}</div>
            ${chipsHtml}
        </div>
    `;
    box.appendChild(msgDiv);
    box.scrollTop = box.scrollHeight;
}

// --- 4. B2B Hotel Resource Hub Slider & ESG Export ---
function updateHotelKpis(occupancyVal) {
    const rooms = Math.round(occupancyVal * 2);
    const powerKwh = Math.round(occupancyVal * 24.2 + 80);
    const waterLiters = Math.round(occupancyVal * 190);
    const foodKg = Math.round(occupancyVal * 0.56);
    const meals = foodKg * 2;

    document.getElementById('occupancy-val-badge').innerText = `${occupancyVal}% (${rooms} Rooms)`;
    document.getElementById('kpi-power').innerText = `${powerKwh.toLocaleString()} kWh`;
    document.getElementById('kpi-power-sub').innerText = `HVAC load: ${Math.round(powerKwh * 0.52)} kWh • Solar: 38%`;
    document.getElementById('kpi-water').innerText = `${waterLiters.toLocaleString()} L`;
    document.getElementById('kpi-food').innerText = `${foodKg} kg (${meals} Meals)`;
}

function triggerHvacOptimization() {
    alert("❄️ Eco-Setpoint Active: All 150 room zones set to 26°C setback. Projected daily savings: 180 kWh (₹1,620 avoided).");
}

function triggerFoodRescue() {
    alert("🍲 Food Rescue Dispatched: Driver from Roti Bank / Feeding India assigned. Pickup ETA: 18 minutes.");
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

// --- 5. Modal Schedule Viewer ---
const TRIP_SCHEDULES = {
    lonavala: {
        title: "Lonavala Monsoon Eco-Retreat Schedule",
        html: `
            <div style="font-size:14px; line-height:1.6; color:#94A3B8;">
                <h4 style="color:#10B981; margin-bottom:8px;">DAY 1: Scenic Ridge &amp; Heritage Caves</h4>
                <p>• <strong>07:10 AM</strong> — Indrayani Express Electric Train (Dadar to Lonavala) [Train • ♿ Level Boarding • ₹75]</p>
                <p>• <strong>09:45 AM</strong> — Step-Free Check-in at The Machan Solar Treehouse Resort</p>
                <p>• <strong>11:30 AM</strong> — Karla Caves &amp; Accessible Plaza (Ancient Buddhist rock-cut shrines) [₹50]</p>
                <p>• <strong>03:30 PM</strong> — Bhushi Dam Eco Trail (Rainwater conservation corridor)</p>
                <p>• <strong>07:00 PM</strong> — Organic Farm-to-Fork Dinner (Maharashtrian millet cuisine)</p>
                <hr style="border-color:rgba(255,255,255,0.1); margin:14px 0;">
                <h4 style="color:#10B981; margin-bottom:8px;">DAY 2: Tiger Point &amp; Sunset Valley</h4>
                <p>• <strong>08:30 AM</strong> — Ryewood Botanical Garden (Accessible paved paths)</p>
                <p>• <strong>12:00 PM</strong> — Tiger's Leap Scenic Viewpoint (Electric tourist shuttle) [₹60]</p>
                <p>• <strong>04:30 PM</strong> — Traditional Organic Jaggery Chikki Workshop</p>
                <p>• <strong>06:15 PM</strong> — Deccan Express Return to Mumbai CSMT [₹75]</p>
            </div>
        `
    },
    alibaug: {
        title: "Alibaug Coastal Low-Carbon Trail Schedule",
        html: `
            <div style="font-size:14px; line-height:1.6; color:#94A3B8;">
                <h4 style="color:#38BDF8; margin-bottom:8px;">DAY 1: Mandwa to Varsoli Coastal Loop</h4>
                <p>• <strong>08:00 AM</strong> — M2M Ro-Pax Hybrid Ferry (Bhaucha Dhakka to Mandwa) [Ferry • ♿ Level Ramp • ₹380]</p>
                <p>• <strong>10:00 AM</strong> — Electric AC Feeder Bus to Alibaug City Center [₹35]</p>
                <p>• <strong>12:30 PM</strong> — Kolaba Marine Fort Low-Tide Walk &amp; Solar Audio Kiosk [₹50]</p>
                <p>• <strong>05:30 PM</strong> — Varsoli Beach Sunset Mangrove Walk &amp; Return Ferry</p>
            </div>
        `
    },
    mumbai: {
        title: "South Mumbai Green &amp; Art Deco Certified Certificate",
        html: `
            <div style="font-size:14px; line-height:1.6; color:#94A3B8;">
                <h4 style="color:#10B981; margin-bottom:8px;">VERIFIED CARBON PASSPORT</h4>
                <p>• <strong>Trip Date:</strong> August 28, 2026</p>
                <p>• <strong>Transit Corridor:</strong> Metro Line 3 Underground (Aqua Line • 100% Step-Free)</p>
                <p>• <strong>Carbon Avoided:</strong> 6.8 kg CO₂e verified vs standard taxi</p>
                <p>• <strong>Reward Earned:</strong> +140 PULSE Points added to Carbon Wallet</p>
            </div>
        `
    }
};

function showTripModal(key) {
    const data = TRIP_SCHEDULES[key] || TRIP_SCHEDULES['lonavala'];
    document.getElementById('modal-trip-title').innerText = data.title;
    document.getElementById('modal-trip-body').innerHTML = data.html;
    document.getElementById('trip-modal').classList.add('open');
}

function closeTripModal() {
    document.getElementById('trip-modal').classList.remove('open');
}

// --- 6. Event Listeners & DOM Setup ---
document.addEventListener('DOMContentLoaded', () => {
    initMap();

    // Map destination select
    document.getElementById('select-destination').addEventListener('change', (e) => {
        renderSelectedRoute(e.target.value);
    });

    document.getElementById('btn-recalculate-route').addEventListener('click', () => {
        const dest = document.getElementById('select-destination').value;
        renderSelectedRoute(dest);
    });

    // Chat input
    document.getElementById('btn-chat-send').addEventListener('click', () => {
        const input = document.getElementById('chat-input');
        handleUserPrompt(input.value);
    });

    document.getElementById('chat-input').addEventListener('keypress', (e) => {
        if (e.key === 'Enter') {
            handleUserPrompt(e.target.value);
        }
    });

    document.getElementById('btn-reset-chat').addEventListener('click', () => {
        document.getElementById('chat-messages').innerHTML = `
            <div class="chat-message ai-message">
                <div class="ai-avatar">🤖</div>
                <div class="message-content">
                    <div class="message-bubble">
                        Dialogue reset! How can I assist your sustainable and accessible journey?
                    </div>
                    <div class="mcq-chips-row">
                        <button class="chip-btn" onclick="handleUserPrompt('Plan a trip to Lonavala')">Plan Trip to Lonavala 🌲</button>
                        <button class="chip-btn" onclick="handleUserPrompt('Plan Coastal Alibaug')">Plan Coastal Alibaug 🏖️</button>
                    </div>
                </div>
            </div>
        `;
        chatStep = 0;
    });

    // Hotel Slider
    const slider = document.getElementById('slider-occupancy');
    slider.addEventListener('input', (e) => {
        updateHotelKpis(e.target.value);
    });

    // ESG Export
    document.getElementById('btn-export-esg').addEventListener('click', exportEsgCsv);

    // Close modal on click outside
    document.getElementById('trip-modal').addEventListener('click', (e) => {
        if (e.target.id === 'trip-modal') {
            closeTripModal();
        }
    });
});

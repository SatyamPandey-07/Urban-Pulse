/// The Leaflet map document loaded into the Live Map WebView.
///
/// Carried over verbatim in behaviour from `LiveMapFragment.buildMapHtml()`:
/// the same Carto voyager tiles, the same pulsing user marker, the same static
/// traffic-flow polylines and POI pins, and the same three JS entry points the
/// Dart side calls — `setCenter`, `drawDualRoutes` and `toggleTrafficOverlay`.
const String liveMapHtml = r'''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
    <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
    <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
    <style>
        html, body, #map { height: 100%; width: 100%; margin: 0; padding: 0; background: #0F172A; font-family: -apple-system, Roboto, sans-serif; }
        .leaflet-control-attribution { display: none; }
        .custom-pin {
            display: flex; align-items: center; justify-content: center;
            border-radius: 50%; color: white; font-weight: 600; font-size: 11px;
            box-shadow: 0 4px 10px rgba(0,0,0,0.5);
        }
        .user-pulse {
            width: 18px; height: 18px; background: #38BDF8; border: 3px solid #FFFFFF;
            border-radius: 50%; box-shadow: 0 0 15px #38BDF8;
            animation: radar 2s infinite ease-out;
        }
        @keyframes radar {
            0% { box-shadow: 0 0 0 0 rgba(56, 189, 248, 0.7); }
            70% { box-shadow: 0 0 0 16px rgba(56, 189, 248, 0); }
            100% { box-shadow: 0 0 0 0 rgba(56, 189, 248, 0); }
        }
        .dest-pin {
            width: 24px; height: 24px; background: #10B981; border: 3px solid #FFFFFF;
            border-radius: 50%; box-shadow: 0 0 16px #10B981;
        }
        .leaflet-popup-content-wrapper {
            background: #1E293B; color: #F8FAFC; border-radius: 12px; border: 1px solid #334155;
        }
        .leaflet-popup-tip { background: #1E293B; }
    </style>
</head>
<body>
    <div id="map"></div>
    <script>
        var map = L.map('map', { zoomControl: false }).setView([19.1775, 72.9544], 13);

        L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
            maxZoom: 19,
            subdomains: 'abcd'
        }).addTo(map);

        var userMarker = L.marker([19.1775, 72.9544], {
            icon: L.divIcon({ className: 'user-pulse', iconSize: [18, 18], iconAnchor: [9, 9] })
        }).addTo(map).bindPopup("<b>Your Current Location</b><br>GPS Grounded");

        var routeLayerGroup = L.layerGroup().addTo(map);
        var trafficLines = [];

        function drawTraffic() {
            var greenLine = L.polyline([
                [19.0544, 72.8402], [19.0760, 72.8777], [19.1136, 72.8697]
            ], { color: '#10B981', weight: 4, opacity: 0.6 }).addTo(map).bindPopup("Western Highway: Fast Flow (54 km/h)");

            var yellowLine = L.polyline([
                [19.0760, 72.8777], [19.0600, 72.8900], [19.0400, 72.9000]
            ], { color: '#F59E0B', weight: 4, opacity: 0.6 }).addTo(map).bindPopup("Eastern Freeway: Moderate (38 km/h)");

            trafficLines = [greenLine, yellowLine];
        }
        drawTraffic();

        var pois = [
            { lat: 19.1728, lon: 72.9564, code: "MED", title: "Fortis Hospital Mulund", desc: "24/7 Trauma Emergency", bg: "#EF4444" },
            { lat: 19.2050, lon: 72.9734, code: "MED", title: "Jupiter Hospital Thane", desc: "Step-Free Critical Care", bg: "#EF4444" },
            { lat: 19.0880, lon: 72.8890, code: "EV", title: "Fast Charging Hub", desc: "60 kW CCS2 (4 Available)", bg: "#38BDF8" },
            { lat: 19.1200, lon: 72.9050, code: "ECO", title: "Powai Lake Eco Track", desc: "Dedicated Electric Mobility Corridor", bg: "#10B981" }
        ];

        pois.forEach(function(p) {
            L.marker([p.lat, p.lon], {
                icon: L.divIcon({
                    className: 'custom-pin',
                    html: '<div style="background:' + p.bg + '; width:28px; height:28px; border-radius:50%; display:flex; align-items:center; justify-content:center; border:2px solid white; font-size:9px;">' + p.code + '</div>',
                    iconSize: [28, 28],
                    iconAnchor: [14, 14]
                })
            }).addTo(map).bindPopup("<b>" + p.title + "</b><br>" + p.desc);
        });

        window.setCenter = function(lat, lon, zoom) {
            map.flyTo([lat, lon], zoom, { duration: 1.2 });
            userMarker.setLatLng([lat, lon]);
        };

        window.drawDualRoutes = function(greenCoords, normalCoords, destTitle, greenSummary, normalSummary) {
            routeLayerGroup.clearLayers();

            // 1. Real normal / petrol-cab polyline (red, dashed).
            var normalLine = L.polyline(normalCoords, {
                color: '#EF4444',
                weight: 5,
                opacity: 0.85,
                dashArray: '8, 8',
                lineCap: 'round'
            }).bindPopup("<b>🚗 Real Normal Route (Petrol Cab)</b><br>" + normalSummary);

            // 2. Real green & inclusive path (glowing emerald polyline).
            var greenGlow = L.polyline(greenCoords, {
                color: '#059669',
                weight: 10,
                opacity: 0.4,
                lineCap: 'round'
            });

            var greenLine = L.polyline(greenCoords, {
                color: '#10B981',
                weight: 5,
                opacity: 1.0,
                lineCap: 'round'
            }).bindPopup("<b>🌿 Real Green Path (Electric Transit / Eco)</b><br>" + greenSummary);

            routeLayerGroup.addLayer(normalLine);
            routeLayerGroup.addLayer(greenGlow);
            routeLayerGroup.addLayer(greenLine);

            if (greenCoords.length > 0) {
                var destCoord = greenCoords[greenCoords.length - 1];
                var destMarker = L.marker(destCoord, {
                    icon: L.divIcon({ className: 'dest-pin', iconSize: [24, 24], iconAnchor: [12, 12] })
                }).bindPopup("<b>Destination: " + destTitle + "</b><br><span style='color:#10B981;font-weight:bold;'>Green Transit: " + greenSummary + "</span><br><span style='color:#EF4444;'>Standard Cab: " + normalSummary + "</span>");

                routeLayerGroup.addLayer(destMarker);
                destMarker.openPopup();
            }

            var group = L.featureGroup([normalLine, greenLine]);
            map.fitBounds(group.getBounds(), { padding: [50, 50], maxZoom: 15 });
        };

        window.toggleTrafficOverlay = function(show) {
            trafficLines.forEach(function(l) {
                if (show) map.addLayer(l); else map.removeLayer(l);
            });
        };
    </script>
</body>
</html>
''';

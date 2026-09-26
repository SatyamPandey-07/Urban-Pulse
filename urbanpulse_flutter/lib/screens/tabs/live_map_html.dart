/// The Leaflet map document loaded into the Live Map WebView.
///
/// Keeps the structure of `LiveMapFragment.buildMapHtml()` — the same Carto
/// voyager tiles, the same pulsing user marker, the same dual-route rendering —
/// but the traffic overlay and the POI pins are no longer drawn from coordinates
/// baked into the page. Both are now injected from real API responses via
/// `setTrafficSegment` and `setPois`, alongside the original `setCenter`,
/// `drawDualRoutes` and `toggleTrafficOverlay` entry points.
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
        // Initialize Leaflet map
        var map = L.map('map', { zoomControl: false }).setView([19.0760, 72.8777], 13);

        // Primary clean OpenStreetMap tiles (no watermarks, no API key required)
        var osmLayer = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
            maxZoom: 19,
            attribution: '© OpenStreetMap'
        }).addTo(map);

        setTimeout(function() {
            if (map) map.invalidateSize();
        }, 350);
        window.addEventListener('resize', function() {
            if (map) map.invalidateSize();
        });

        var userMarker = L.marker([19.0760, 72.8777], {
            icon: L.divIcon({ className: 'user-pulse', iconSize: [18, 18], iconAnchor: [9, 9] })
        }).addTo(map).bindPopup("<b>Your Current Location</b><br>GPS Grounded");

        var routeLayerGroup = L.layerGroup().addTo(map);
        var trafficLayerGroup = L.layerGroup().addTo(map);
        var poiLayerGroup = L.layerGroup().addTo(map);
        var trafficVisible = true;

        // Real TomTom flow-segment geometry, coloured by how far below free flow
        // the corridor is actually running. Called from Dart with live data.
        window.setTrafficSegment = function(coords, label, congestionPercent) {
            trafficLayerGroup.clearLayers();
            if (!coords || coords.length < 2) return;
            var color = congestionPercent < 25 ? '#10B981'
                      : congestionPercent < 55 ? '#F59E0B'
                      : '#EF4444';
            var line = L.polyline(coords, { color: color, weight: 5, opacity: 0.75 })
                        .bindPopup(label);
            trafficLayerGroup.addLayer(line);
            if (!trafficVisible) map.removeLayer(trafficLayerGroup);
        };

        // Real nearby POIs from the TomTom POI search, injected from Dart.
        window.setPois = function(pois) {
            poiLayerGroup.clearLayers();
            pois.forEach(function(p) {
                var marker = L.marker([p.lat, p.lon], {
                    icon: L.divIcon({
                        className: 'custom-pin',
                        html: '<div style="background:' + p.bg + '; width:28px; height:28px; border-radius:50%; display:flex; align-items:center; justify-content:center; border:2px solid white; font-size:9px;">' + p.code + '</div>',
                        iconSize: [28, 28],
                        iconAnchor: [14, 14]
                    })
                }).bindPopup("<b>" + p.title + "</b><br>" + p.desc);
                poiLayerGroup.addLayer(marker);
            });
        };

        window.setCenter = function(lat, lon, zoom) {
            if (map) {
                map.invalidateSize();
                map.flyTo([lat, lon], zoom, { duration: 1.2 });
            }
            if (userMarker) {
                userMarker.setLatLng([lat, lon]);
            }
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
            trafficVisible = show;
            if (show) map.addLayer(trafficLayerGroup); else map.removeLayer(trafficLayerGroup);
        };
    </script>
</body>
</html>
''';

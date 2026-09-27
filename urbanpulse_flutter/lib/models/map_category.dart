import 'package:flutter/material.dart';

/// A kind of place the Live Map can show around you.
enum MapCategory {
  food('Food', Icons.restaurant_rounded, Color(0xFFEF4444), 'restaurant', ['["amenity"~"^(restaurant|cafe|fast_food|food_court)\$"]']),
  hotels('Hotels', Icons.hotel_rounded, Color(0xFF00A86B), 'hotel', ['["tourism"~"^(hotel|guest_house|hostel|motel|resort)\$"]']),
  attractions('Attractions', Icons.star_rounded, Color(0xFFF59E0B), 'tourist attraction', [
    '["tourism"~"^(attraction|museum|gallery|viewpoint|zoo|theme_park)\$"]',
    '["historic"~"^(monument|memorial|castle|fort|ruins|archaeological_site)\$"]',
  ]),
  hospitals('Hospitals', Icons.local_hospital_rounded, Color(0xFFDC2626), 'hospital', ['["amenity"~"^(hospital|clinic)\$"]']),
  pharmacies('Pharmacies', Icons.medication_rounded, Color(0xFF7C3AED), 'pharmacy', ['["amenity"="pharmacy"]']),
  charging('EV charging', Icons.ev_station_rounded, Color(0xFF0EA5E9), 'electric vehicle station', ['["amenity"="charging_station"]']);

  const MapCategory(this.label, this.icon, this.color, this.query, this.osmFilters);

  final String label;
  final IconData icon;
  final Color color;

  /// What is asked of the search service.
  final String query;

  /// The same thing as OpenStreetMap tag filters.
  final List<String> osmFilters;
}

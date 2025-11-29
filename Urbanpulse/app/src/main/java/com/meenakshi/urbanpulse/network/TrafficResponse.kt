package com.meenakshi.urbanpulse.network

import com.google.gson.annotations.SerializedName

data class TrafficFlowResponse(
    @SerializedName("flowSegmentData")
    val flowData: FlowSegmentData
)

data class FlowSegmentData(
    val frc: String, // Functional Road Class
    val currentSpeed: Int, // km/h
    val freeFlowSpeed: Int, // km/h
    val currentTravelTime: Int, // seconds
    val freeFlowTravelTime: Int, // seconds
    val confidence: Double,
    val roadClosure: Boolean = false,
    @SerializedName("coordinates")
    val coordinates: CoordinateWrapper
)

data class CoordinateWrapper(
    @SerializedName("coordinate")
    val list: List<TrafficCoordinate>
)

data class TrafficCoordinate(
    val latitude: Double,
    val longitude: Double
)
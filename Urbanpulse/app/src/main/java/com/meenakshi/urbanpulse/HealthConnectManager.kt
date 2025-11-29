package com.meenakshi.urbanpulse

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import java.time.temporal.ChronoUnit

class HealthConnectManager(private val context: Context) {

    private val healthConnectClient by lazy { HealthConnectClient.getOrCreate(context) }

    suspend fun hasPermissions(): Boolean {
        val permissions = setOf(
            HealthPermission.getReadPermission(StepsRecord::class)
        )
        return healthConnectClient.permissionController.getGrantedPermissions().containsAll(permissions)
    }

    suspend fun readWeeklySteps(): Map<String, Long> {
        if (!hasPermissions()) return emptyMap()

        val endTime = Instant.now()
        val startTime = endTime.minus(7, ChronoUnit.DAYS)

        val response = healthConnectClient.readRecords(
            ReadRecordsRequest(
                StepsRecord::class,
                timeRangeFilter = TimeRangeFilter.between(startTime, endTime)
            )
        )

        // Group by day (simplified)
        // Real implementation would group by ZoneOffset
        return response.records.groupBy { 
            // Simplified grouping logic
            it.startTime.toString().substring(0, 10) 
        }.mapValues { entry ->
            entry.value.sumOf { it.count }
        }
    }
}

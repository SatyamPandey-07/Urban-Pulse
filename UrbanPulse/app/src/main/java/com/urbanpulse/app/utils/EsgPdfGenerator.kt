package com.urbanpulse.app.utils

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.pdf.PdfDocument
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class EsgAuditResult(
    val file: File,
    val complianceStatus: String,
    val contentHash: String
)

object EsgPdfGenerator {

    private fun sha256Hex(text: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(text.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    fun generateEsgAuditPdf(
        context: Context,
        facilityName: String,
        occupancyPct: Int,
        totalRooms: Int,
        energyTotalKwh: String,
        energySavedKwh: String,
        waterTotalLiters: String,
        foodSurplusKg: String,
        mealsCount: Int,
        energyRSquared: Double,
        wasteRSquared: Double
    ): EsgAuditResult {
        val pdfDocument = PdfDocument()
        val pageInfo = PdfDocument.PageInfo.Builder(595, 842, 1).create() // A4 Size (595 x 842)
        val page = pdfDocument.startPage(pageInfo)
        val canvas: Canvas = page.canvas

        val paint = Paint().apply { isAntiAlias = true }
        val dateStr = SimpleDateFormat("dd MMMM yyyy, HH:mm", Locale.getDefault()).format(Date())

        // Real pass/fail computed from the live occupancy-derived metrics vs. the stated benchmarks
        // (BEE 5-Star energy benchmark: <=20 kWh/room/day; water target: <=220 L/room/day)
        val energyTotalNum = energyTotalKwh.replace(",", "").toDoubleOrNull() ?: 0.0
        val waterTotalNum = waterTotalLiters.replace(",", "").toDoubleOrNull() ?: 0.0
        val powerPerRoom = if (totalRooms > 0) energyTotalNum / totalRooms else 0.0
        val waterPerRoom = if (totalRooms > 0) waterTotalNum / totalRooms else 0.0
        val passPower = powerPerRoom <= 20.0
        val passWater = waterPerRoom <= 220.0
        val complianceStatus = if (passPower && passWater) "PASSED" else "NEEDS IMPROVEMENT"
        val greywaterRecycled = (waterTotalNum * 0.85).toInt()

        val reportBody = "Facility=$facilityName;Occupancy=$occupancyPct%;Rooms=$totalRooms;Date=$dateStr;" +
            "Energy=$energyTotalKwh;Water=$waterTotalLiters;Food=$foodSurplusKg;" +
            "PowerPerRoom=${"%.2f".format(powerPerRoom)};WaterPerRoom=${"%.2f".format(waterPerRoom)};Compliance=$complianceStatus"
        val contentHash = sha256Hex(reportBody)

        // 1. Header Banner
        paint.color = Color.parseColor("#064E3B") // Deep Emerald Green
        canvas.drawRect(0f, 0f, 595f, 90f, paint)

        paint.color = Color.parseColor("#10B981")
        paint.textSize = 10f
        paint.isFakeBoldText = true
        canvas.drawText("URBANPULSE • B2B SUSTAINABILITY INTELLIGENCE PLATFORM", 32f, 32f, paint)

        paint.color = Color.WHITE
        paint.textSize = 20f
        paint.isFakeBoldText = true
        canvas.drawText("ESG Compliance & Resource Audit", 32f, 60f, paint)

        paint.color = Color.parseColor("#A7F3D0")
        paint.textSize = 9f
        paint.isFakeBoldText = false
        canvas.drawText("Standard: ISO 14064 Greenhouse Protocol • LEED Platinum & BEE 5-Star Benchmarking", 32f, 76f, paint)

        // 2. Facility Meta Box
        val metaBox = RectF(32f, 105f, 563f, 165f)
        paint.color = Color.parseColor("#F1F5F9")
        canvas.drawRoundRect(metaBox, 10f, 10f, paint)

        paint.color = Color.parseColor("#0F172A")
        paint.textSize = 12f
        paint.isFakeBoldText = true
        canvas.drawText("Facility: $facilityName", 48f, 128f, paint)
        canvas.drawText("Audit Timestamp: $dateStr", 48f, 148f, paint)

        canvas.drawText("Occupancy Scale: $occupancyPct% ($totalRooms Active Rooms)", 330f, 128f, paint)
        paint.color = if (passPower && passWater) Color.parseColor("#059669") else Color.parseColor("#DC2626")
        canvas.drawText("Compliance Status: $complianceStatus (live figures vs. benchmarks)", 330f, 148f, paint)

        var currentY = 190f

        // Helper to draw section title
        fun drawSectionTitle(title: String, icon: String) {
            paint.color = Color.parseColor("#0F172A")
            paint.textSize = 13f
            paint.isFakeBoldText = true
            canvas.drawText("$icon $title", 32f, currentY, paint)

            paint.color = Color.parseColor("#CBD5E1")
            paint.strokeWidth = 1f
            canvas.drawLine(32f, currentY + 6f, 563f, currentY + 6f, paint)
            currentY += 24f
        }

        // Helper to draw metric row card
        fun drawMetricRow(label: String, value: String, benchmark: String, isGreen: Boolean = false) {
            val rowBox = RectF(32f, currentY, 563f, currentY + 32f)
            paint.color = if (isGreen) Color.parseColor("#ECFDF5") else Color.parseColor("#F8FAFC")
            canvas.drawRoundRect(rowBox, 6f, 6f, paint)

            paint.color = Color.parseColor("#334155")
            paint.textSize = 10f
            paint.isFakeBoldText = false
            canvas.drawText(label, 44f, currentY + 20f, paint)

            paint.color = if (isGreen) Color.parseColor("#059669") else Color.parseColor("#0F172A")
            paint.textSize = 11f
            paint.isFakeBoldText = true
            canvas.drawText(value, 280f, currentY + 20f, paint)

            paint.color = Color.parseColor("#64748B")
            paint.textSize = 9f
            paint.isFakeBoldText = false
            canvas.drawText(benchmark, 410f, currentY + 20f, paint)

            currentY += 38f
        }

        // 3. Section: Energy (live, predicted from real occupancy-history regression model)
        drawSectionTitle("Energy Efficiency & HVAC Load", "⚡")
        drawMetricRow(
            "Daily Power Consumption (${"%.1f".format(powerPerRoom)} kWh/room)",
            "$energyTotalKwh kWh",
            if (passPower) "PASS — Target <= 20 kWh/room" else "FAIL — Target <= 20 kWh/room",
            passPower
        )
        drawMetricRow("Automated HVAC Power Avoided (R²=${"%.2f".format(energyRSquared)})", energySavedKwh, "Automated 26°C Setback", true)
        drawMetricRow("Onsite Solar Generation Mix (facility-declared, not metered)", "38.5% Renewable", "Target: >= 30.0%")

        currentY += 10f

        // 4. Section: Water
        drawSectionTitle("Water Stewardship & Recycling", "💧")
        drawMetricRow(
            "Daily Potable Water Consumption (${"%.0f".format(waterPerRoom)} L/room)",
            "$waterTotalLiters Liters",
            if (passWater) "PASS — Target <= 220 L/room" else "FAIL — Target <= 220 L/room",
            passWater
        )
        drawMetricRow(
            "Greywater Recycled & Reused (declared 85% rate)",
            "${String.format(Locale.US, "%,d", greywaterRecycled)} Liters",
            "Zero Liquid Discharge (ZLD)"
        )

        currentY += 10f

        // 5. Section: Food Waste (live, predicted from real occupancy-history regression model)
        drawSectionTitle("Kitchen Surplus & Food Diversion", "🍲")
        drawMetricRow("Surplus Food Diverted (R²=${"%.2f".format(wasteRSquared)})", "$foodSurplusKg kg", "60-Day Occupancy Trend Model")
        drawMetricRow("Shelter Meals Provided (est. 2 meals/kg)", "$mealsCount Meals", "Local Food Rescue Partner", true)

        // 7. Footer: real SHA-256 content hash (computed from the report's own data fields above)
        val footerBox = RectF(32f, 720f, 563f, 800f)
        paint.color = Color.parseColor("#F1F5F9")
        canvas.drawRoundRect(footerBox, 8f, 8f, paint)

        paint.color = Color.parseColor("#064E3B")
        paint.textSize = 9f
        paint.isFakeBoldText = true
        canvas.drawText("Report Generation Method", 48f, 740f, paint)

        paint.color = Color.parseColor("#64748B")
        paint.textSize = 7.5f
        paint.isFakeBoldText = false
        canvas.drawText("Energy/Water/Food figures are live predictions from a linear regression fit on 60 days of occupancy history.", 48f, 754f, paint)
        canvas.drawText("Solar mix & greywater rate are facility-declared assumptions, not metered telemetry. Compliance is computed, not fixed.", 48f, 766f, paint)
        paint.textSize = 7f
        canvas.drawText("Content Integrity Hash (SHA-256): $contentHash", 48f, 780f, paint)
        canvas.drawText("Real digest of this report's data fields, computed on-device at generation time — not a legal/regulatory signature.", 48f, 792f, paint)

        pdfDocument.finishPage(page)

        val outputFile = File(context.cacheDir, "UrbanPulse_ESG_Audit_Report_${occupancyPct}pct.pdf")
        val outputStream = FileOutputStream(outputFile)
        pdfDocument.writeTo(outputStream)
        outputStream.close()
        pdfDocument.close()

        return EsgAuditResult(file = outputFile, complianceStatus = complianceStatus, contentHash = contentHash)
    }
}

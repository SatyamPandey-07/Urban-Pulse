package com.meenakshi.urbanpulse

import android.content.Intent
import android.os.Bundle
import android.widget.ImageButton
import android.widget.Toast
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView

class GreenRoutePlannerActivity : BaseActivity() {

    private var selectedOption = "Metro"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_green_route_planner)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        val cardMetro = findViewById<MaterialCardView>(R.id.cardOptionMetro)
        val cardBus = findViewById<MaterialCardView>(R.id.cardOptionBus)
        val cardEvCab = findViewById<MaterialCardView>(R.id.cardOptionEvCab)
        val cardTaxi = findViewById<MaterialCardView>(R.id.cardOptionTaxi)
        val btnConfirm = findViewById<MaterialButton>(R.id.btnConfirmGreenRoute)

        val resetStrokes = {
            cardMetro.strokeWidth = 0
            cardBus.strokeWidth = 0
            cardEvCab.strokeWidth = 0
            cardTaxi.strokeWidth = 0
        }

        cardMetro.setOnClickListener {
            resetStrokes()
            cardMetro.strokeWidth = 4
            selectedOption = "Metro"
            btnConfirm.text = "Start Green Metro Journey (+40 Points)"
        }

        cardBus.setOnClickListener {
            resetStrokes()
            cardBus.strokeWidth = 4
            selectedOption = "Bus"
            btnConfirm.text = "Start Electric Bus Journey (+35 Points)"
        }

        cardEvCab.setOnClickListener {
            resetStrokes()
            cardEvCab.strokeWidth = 4
            selectedOption = "EV Cab"
            btnConfirm.text = "Book Accessible EV Cab (+20 Points)"
        }

        cardTaxi.setOnClickListener {
            resetStrokes()
            cardTaxi.strokeWidth = 4
            selectedOption = "Taxi"
            btnConfirm.text = "Standard Taxi Selected (+0 Points)"
        }

        btnConfirm.setOnClickListener {
            Toast.makeText(this, "Journey commenced via $selectedOption. Live carbon tracking active.", Toast.LENGTH_LONG).show()
            finish()
        }
    }
}

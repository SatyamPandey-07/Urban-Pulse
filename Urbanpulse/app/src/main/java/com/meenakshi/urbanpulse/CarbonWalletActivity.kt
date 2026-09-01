package com.meenakshi.urbanpulse

import android.os.Bundle
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import com.google.android.material.button.MaterialButton

class CarbonWalletActivity : BaseActivity() {

    private var points = 1240

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_carbon_wallet)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        val tvCredits = findViewById<TextView>(R.id.tvPulseCredits)
        val btnRedeemOrchid = findViewById<MaterialButton>(R.id.btnRedeemOrchid)
        val btnRedeemEv = findViewById<MaterialButton>(R.id.btnRedeemEv)

        btnRedeemOrchid.setOnClickListener {
            if (points >= 400) {
                points -= 400
                tvCredits.text = "$points pts"
                btnRedeemOrchid.isEnabled = false
                btnRedeemOrchid.text = "Voucher Code: ORCHID-ECO-15"
                Toast.makeText(this, "Orchid Eco-Resort voucher unlocked! Saved to your profile.", Toast.LENGTH_LONG).show()
            }
        }

        btnRedeemEv.setOnClickListener {
            if (points >= 250) {
                points -= 250
                tvCredits.text = "$points pts"
                btnRedeemEv.isEnabled = false
                btnRedeemEv.text = "Voucher Code: TATA-EV-FREE"
                Toast.makeText(this, "Free EV Charging voucher unlocked!", Toast.LENGTH_LONG).show()
            }
        }
    }
}

package com.urbanpulse.app

import android.os.Bundle
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import com.google.android.material.button.MaterialButton
import java.util.Locale

class CarbonWalletActivity : BaseActivity() {

    private lateinit var tvCredits: TextView
    private lateinit var tvCo2Saved: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_carbon_wallet)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        tvCredits = findViewById(R.id.tvPulseCredits)
        tvCo2Saved = findViewById(R.id.tvTotalCo2Saved)
        val btnRedeemOrchid = findViewById<MaterialButton>(R.id.btnRedeemOrchid)
        val btnRedeemEv = findViewById<MaterialButton>(R.id.btnRedeemEv)

        refreshBalance()

        btnRedeemOrchid.setOnClickListener {
            if (GamificationManager.spendPulse(400)) {
                refreshBalance()
                btnRedeemOrchid.isEnabled = false
                btnRedeemOrchid.text = "Voucher Code: ORCHID-ECO-15"
                Toast.makeText(this, "Orchid Eco-Resort voucher unlocked! Saved to your profile.", Toast.LENGTH_LONG).show()
            } else {
                Toast.makeText(this, "Not enough PULSE credits yet — keep taking green trips!", Toast.LENGTH_SHORT).show()
            }
        }

        btnRedeemEv.setOnClickListener {
            if (GamificationManager.spendPulse(250)) {
                refreshBalance()
                btnRedeemEv.isEnabled = false
                btnRedeemEv.text = "Voucher Code: TATA-EV-FREE"
                Toast.makeText(this, "Free EV Charging voucher unlocked!", Toast.LENGTH_LONG).show()
            } else {
                Toast.makeText(this, "Not enough PULSE credits yet — keep taking green trips!", Toast.LENGTH_SHORT).show()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        refreshBalance()
    }

    private fun refreshBalance() {
        tvCredits.text = String.format(Locale.US, "%,d pts", GamificationManager.getPulse())
        val co2Kg = GamificationManager.getCo2Saved() / 1000.0
        tvCo2Saved.text = String.format(Locale.US, "%.1f kg", co2Kg)
    }
}

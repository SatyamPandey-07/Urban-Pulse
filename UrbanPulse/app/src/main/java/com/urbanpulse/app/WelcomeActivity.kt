package com.urbanpulse.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton

class WelcomeActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_welcome)

        findViewById<MaterialButton>(R.id.btnCreateAccount).setOnClickListener {
            startActivity(Intent(this, SignUpActivity::class.java))
        }

        findViewById<MaterialButton>(R.id.btnLogin).setOnClickListener {
            startActivity(Intent(this, LoginActivity::class.java))
        }

        findViewById<MaterialButton>(R.id.btnDemoDirect).setOnClickListener {
            val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
            prefs.edit()
                .putString("user_email", "demo.traveler@urbanpulse.ai")
                .putBoolean("is_logged_in", true)
                .apply()

            Toast.makeText(this, "Welcome! Logged in as Demo Explorer.", Toast.LENGTH_SHORT).show()
            val intent = Intent(this, MainActivity::class.java)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            startActivity(intent)
            finish()
        }
    }
}

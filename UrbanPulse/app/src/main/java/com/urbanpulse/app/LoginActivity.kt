package com.urbanpulse.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.android.material.button.MaterialButton
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.textfield.TextInputEditText
import kotlinx.coroutines.launch

class LoginActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_login)

        val emailEditText = findViewById<TextInputEditText>(R.id.emailEditText)
        val passwordEditText = findViewById<TextInputEditText>(R.id.passwordEditText)
        val loginButton = findViewById<MaterialButton>(R.id.loginButton)
        val btnDemoLogin = findViewById<MaterialButton>(R.id.btnDemoLogin)
        val signUpPromptTextView = findViewById<TextView>(R.id.signUpPromptTextView)

        fun performLogin(email: String) {
            val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
            prefs.edit()
                .putString("user_email", email)
                .putBoolean("is_logged_in", true)
                .apply()

            Toast.makeText(this, "Logged in as $email (Demo Mode Active)", Toast.LENGTH_SHORT).show()
            val intent = Intent(this, MainActivity::class.java)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            startActivity(intent)
            finish()
        }

        loginButton.setOnClickListener {
            val email = emailEditText.text.toString().trim()
            val password = passwordEditText.text.toString()

            if (email.isEmpty() || password.isEmpty()) {
                Toast.makeText(this, "Please enter email and password", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }

            val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
            val savedEmail = prefs.getString("user_email", "") ?: ""

            val isValid = (email == "admin@123.com" && password == "password") ||
                          (savedEmail.isNotEmpty() && email == savedEmail) ||
                          (email.contains("@") && password.length >= 6)

            if (isValid) {
                lifecycleScope.launch {
                    try {
                        AuthManager.signIn(email, password)
                    } catch (e: Exception) {
                        // Offline / demo fallback
                    }
                }
                performLogin(email)
            } else {
                MaterialAlertDialogBuilder(this)
                    .setTitle("Login Failed")
                    .setMessage("Invalid email or password. Password must be at least 6 characters.")
                    .setPositiveButton("OK", null)
                    .show()
            }
        }

        btnDemoLogin.setOnClickListener {
            emailEditText.setText("demo.traveler@urbanpulse.ai")
            passwordEditText.setText("urbanpulse2026")
            performLogin("demo.traveler@urbanpulse.ai")
        }

        signUpPromptTextView.setOnClickListener {
            startActivity(Intent(this, SignUpActivity::class.java))
            finish()
        }
    }
}

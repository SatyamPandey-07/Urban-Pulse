package com.meenakshi.urbanpulse

import android.content.Intent
import android.os.Bundle
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.textfield.TextInputEditText

class LoginActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_login)

        val emailEditText = findViewById<TextInputEditText>(R.id.emailEditText)
        val passwordEditText = findViewById<TextInputEditText>(R.id.passwordEditText)
        val loginButton = findViewById<MaterialButton>(R.id.loginButton)
        val signUpPromptTextView = findViewById<TextView>(R.id.signUpPromptTextView)

        loginButton.setOnClickListener {
            val email = emailEditText.text.toString()
            val password = passwordEditText.text.toString()

            if (email == "admin@123.com" && password == "password") {
                startActivity(Intent(this, MainActivity::class.java))
                finish()
            } else {
                MaterialAlertDialogBuilder(this)
                    .setTitle("Login Failed")
                    .setMessage("Invalid email or password.")
                    .setPositiveButton("OK", null)
                    .show()
            }
        }

        signUpPromptTextView.setOnClickListener {
            startActivity(Intent(this, SignUpActivity::class.java))
        }
    }
}

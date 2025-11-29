package com.meenakshi.urbanpulse

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatDelegate
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

class ProfileFragment : Fragment() {

    private lateinit var prefs: SharedPreferences
    private lateinit var tvAvatar: TextView
    private lateinit var tvUserName: TextView
    private lateinit var tvUserEmail: TextView

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val view = inflater.inflate(R.layout.fragment_profile, container, false)
        val recyclerView = view.findViewById<RecyclerView>(R.id.settingsRecyclerView)
        tvAvatar = view.findViewById(R.id.tvAvatar)
        tvUserName = view.findViewById(R.id.tvUserName)
        tvUserEmail = view.findViewById(R.id.tvUserEmail)
        
        prefs = requireContext().getSharedPreferences("app_prefs", Context.MODE_PRIVATE)

        setupProfileHeader()

        recyclerView.layoutManager = LinearLayoutManager(context)
        recyclerView.adapter = SettingsAdapter(getSettingsList()) { item ->
            handleSettingClick(item)
        }
        
        return view
    }

    private fun setupProfileHeader() {
        val user = AuthManager.currentUser
        if (user != null) {
            tvUserEmail.text = user.email
            
            CoroutineScope(Dispatchers.Main).launch {
                val name = AuthManager.getUserName() ?: "User"
                tvUserName.text = name
                if (name.isNotEmpty()) {
                    tvAvatar.text = name.first().toString().uppercase()
                }
            }
        }
    }

    private fun getSettingsList(): List<SettingItem> {
        val currentLoc = prefs.getString("home_city", "Mumbai") + ", " + prefs.getString("home_country", "IN")
        val currentLang = if (prefs.getString("language", "en") == "hi") getString(R.string.lang_hindi) else getString(R.string.lang_english)
        val currentAccent = prefs.getString("theme_color", "green")?.replaceFirstChar { it.uppercase() } ?: "Green"
        
        return listOf(
            SettingItem(SettingType.APPEARANCE, R.string.pref_appearance, R.string.pref_appearance_desc, R.drawable.ic_light_mode, "#FDE293"),
            SettingItem(SettingType.ACCENT_COLOR, R.string.pref_accent_color, 0, R.drawable.ic_color_lens, "#E1BEE7", currentAccent),
            SettingItem(SettingType.LOCATION, R.string.pref_home_location, 0, R.drawable.ic_location_pin, "#C3E7A1", currentLoc),
            SettingItem(SettingType.UNITS, R.string.pref_app_units, R.string.pref_app_units_desc, R.drawable.ic_dashboard, "#D3E3FD"),
            SettingItem(SettingType.LANGUAGE, R.string.pref_language, 0, R.drawable.ic_yatri_ai, "#FBCFE8", currentLang),
            SettingItem(SettingType.SIGN_OUT, R.string.pref_sign_out, 0, R.drawable.ic_send_24, "#FFCDD2", "") // Reddish for sign out
        )
    }

    private fun handleSettingClick(item: SettingItem) {
        when (item.type) {
            SettingType.APPEARANCE -> showThemeDialog()
            SettingType.ACCENT_COLOR -> showAccentColorDialog()
            SettingType.LOCATION -> showLocationDialog()
            SettingType.UNITS -> showUnitsDialog()
            SettingType.LANGUAGE -> showLanguageDialog()
            SettingType.SIGN_OUT -> signOut()
            else -> {}
        }
    }
    
    private fun signOut() {
        AuthManager.signOut(requireContext())
        val intent = Intent(requireContext(), WelcomeActivity::class.java)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        startActivity(intent)
    }

    private fun showThemeDialog() {
        val themes = arrayOf(getString(R.string.theme_light), getString(R.string.theme_dark), getString(R.string.theme_system))
        AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.dialog_theme_title))
            .setItems(themes) { _, which ->
                val mode = when (which) {
                    0 -> AppCompatDelegate.MODE_NIGHT_NO
                    1 -> AppCompatDelegate.MODE_NIGHT_YES
                    else -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
                }
                AppCompatDelegate.setDefaultNightMode(mode)
                prefs.edit().putInt("theme_mode", mode).apply()
            }
            .show()
    }
    
    private fun showAccentColorDialog() {
        val colors = arrayOf("Green", "Blue", "Purple", "Orange", "Pink", "Teal")
        val colorKeys = arrayOf("green", "blue", "purple", "orange", "pink", "teal")
        
        AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.dialog_accent_title))
            .setItems(colors) { _, which ->
                ThemeUtils.saveThemeColor(requireContext(), colorKeys[which])
                activity?.recreate()
            }
            .show()
    }

    private fun showUnitsDialog() {
        val units = arrayOf(getString(R.string.unit_metric), getString(R.string.unit_imperial))
        AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.dialog_units_title))
            .setItems(units) { _, which ->
                val unit = if (which == 0) "metric" else "imperial"
                prefs.edit().putString("units", unit).apply()
            }
            .show()
    }

    private fun showLocationDialog() {
        val dialogView = LayoutInflater.from(requireContext()).inflate(R.layout.dialog_location_input, null)
        val etCity = dialogView.findViewById<EditText>(R.id.etCity)
        val etCountry = dialogView.findViewById<EditText>(R.id.etCountry)
        
        etCity.setText(prefs.getString("home_city", ""))
        etCountry.setText(prefs.getString("home_country", ""))

        AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.dialog_location_title))
            .setView(dialogView)
            .setPositiveButton(getString(R.string.save)) { _, _ ->
                val city = etCity.text.toString()
                val country = etCountry.text.toString()
                prefs.edit()
                    .putString("home_city", city)
                    .putString("home_country", country)
                    .apply()
                refreshFragment()
            }
            .setNegativeButton(getString(R.string.cancel), null)
            .show()
    }

    private fun showLanguageDialog() {
        val langs = arrayOf(getString(R.string.lang_english), getString(R.string.lang_hindi))
        AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.dialog_language_title))
            .setItems(langs) { _, which ->
                val code = if (which == 0) "en" else "hi"
                prefs.edit().putString("language", code).apply()
                setLocale(code)
            }
            .show()
    }

    private fun setLocale(languageCode: String) {
        val locale = Locale(languageCode)
        Locale.setDefault(locale)
        val config = Configuration()
        config.setLocale(locale)
        requireContext().resources.updateConfiguration(config, requireContext().resources.displayMetrics)
        
        activity?.recreate()
    }

    private fun refreshFragment() {
        val recyclerView = view?.findViewById<RecyclerView>(R.id.settingsRecyclerView)
        recyclerView?.adapter = SettingsAdapter(getSettingsList()) { handleSettingClick(it) }
    }
}

package com.meenakshi.urbanpulse

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

class EmergencyContactsManager(context: Context) {
    private val prefs = context.getSharedPreferences("emergency_contacts", Context.MODE_PRIVATE)
    private val gson = Gson()

    fun getContacts(): List<EmergencyContact> {
        val json = prefs.getString("contacts", null) ?: return emptyList()
        val type = object : TypeToken<List<EmergencyContact>>() {}.type
        return gson.fromJson(json, type)
    }

    fun saveContacts(contacts: List<EmergencyContact>) {
        val json = gson.toJson(contacts)
        prefs.edit().putString("contacts", json).apply()
    }

    fun addContact(contact: EmergencyContact) {
        val list = getContacts().toMutableList()
        list.add(contact)
        list.sortBy { it.priority }
        saveContacts(list)
    }
    
    fun removeContact(contact: EmergencyContact) {
        val list = getContacts().toMutableList()
        list.remove(contact) // Simplistic equality check
        saveContacts(list)
    }
}

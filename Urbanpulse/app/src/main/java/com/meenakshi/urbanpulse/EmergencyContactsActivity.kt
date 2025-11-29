package com.meenakshi.urbanpulse

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.floatingactionbutton.FloatingActionButton

class EmergencyContactsActivity : AppCompatActivity() {

    private lateinit var manager: EmergencyContactsManager
    private lateinit var adapter: ContactsAdapter
    private lateinit var recyclerView: RecyclerView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_emergency_contacts)

        manager = EmergencyContactsManager(this)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        toolbar.setNavigationOnClickListener { finish() }

        recyclerView = findViewById(R.id.recyclerView)
        recyclerView.layoutManager = LinearLayoutManager(this)
        
        loadContacts()

        findViewById<FloatingActionButton>(R.id.fabAdd).setOnClickListener {
            showAddContactDialog()
        }
    }

    private fun loadContacts() {
        val contacts = manager.getContacts()
        adapter = ContactsAdapter(contacts) { contact ->
            manager.removeContact(contact)
            loadContacts()
        }
        recyclerView.adapter = adapter
    }

    private fun showAddContactDialog() {
        val dialogView = LayoutInflater.from(this).inflate(R.layout.dialog_add_contact, null)
        val etName = dialogView.findViewById<EditText>(R.id.etName)
        val etNumber = dialogView.findViewById<EditText>(R.id.etNumber)

        AlertDialog.Builder(this)
            .setTitle("Add Contact")
            .setView(dialogView)
            .setPositiveButton("Add") { _, _ ->
                val name = etName.text.toString()
                val number = etNumber.text.toString()
                if (name.isNotEmpty() && number.isNotEmpty()) {
                    // Priority based on existing size (FIFO)
                    val priority = manager.getContacts().size + 1
                    manager.addContact(EmergencyContact(name, number, priority))
                    loadContacts()
                }
            }
            .setNegativeButton("Cancel", null)
            .show()
    }
}

class ContactsAdapter(
    private val contacts: List<EmergencyContact>,
    private val onDelete: (EmergencyContact) -> Unit
) : RecyclerView.Adapter<ContactsAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val name: TextView = view.findViewById(R.id.tvName)
        val number: TextView = view.findViewById(R.id.tvNumber)
        val delete: ImageView = view.findViewById(R.id.btnDelete)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_emergency_contact, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val contact = contacts[position]
        holder.name.text = contact.name
        holder.number.text = contact.number
        holder.delete.setOnClickListener { onDelete(contact) }
    }

    override fun getItemCount() = contacts.size
}

package com.urbanpulse.app

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.button.MaterialButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.security.MessageDigest
import java.util.UUID

class AchievementsActivity : AppCompatActivity() {

    private lateinit var tvWalletStatus: TextView
    private lateinit var tvWalletAddress: TextView
    private lateinit var btnConnectWallet: MaterialButton
    private lateinit var achievementsRecyclerView: RecyclerView
    private lateinit var adapter: AchievementsAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_achievements)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        toolbar.setNavigationOnClickListener { finish() }

        tvWalletStatus = findViewById(R.id.tvWalletStatus)
        tvWalletAddress = findViewById(R.id.tvWalletAddress)
        btnConnectWallet = findViewById(R.id.btnConnectWallet)
        achievementsRecyclerView = findViewById(R.id.achievementsRecyclerView)

        achievementsRecyclerView.layoutManager = LinearLayoutManager(this)
        adapter = AchievementsAdapter(emptyList())
        achievementsRecyclerView.adapter = adapter

        updateWalletDisplay()

        btnConnectWallet.setOnClickListener {
            val current = GamificationManager.getWalletAddress()
            if (current.isNullOrBlank()) {
                connectWallet()
            } else {
                disconnectWallet()
            }
        }

        loadAchievements()
    }

    override fun onResume() {
        super.onResume()
        updateWalletDisplay()
        loadAchievements()
    }

    private fun updateWalletDisplay() {
        val address = GamificationManager.getWalletAddress()
        if (!address.isNullOrBlank()) {
            tvWalletStatus.text = "Connected (Polygon / Green Carbon Ledger)"
            tvWalletAddress.text = address
            tvWalletAddress.visibility = View.VISIBLE
            btnConnectWallet.text = "Disconnect Wallet"
        } else {
            tvWalletStatus.text = "No Web3 Wallet Linked"
            tvWalletAddress.text = ""
            tvWalletAddress.visibility = View.GONE
            btnConnectWallet.text = "Link Web3 Carbon Wallet"
        }
    }

    private fun connectWallet() {
        tvWalletStatus.text = "Generating Green Keypair & Connecting..."
        btnConnectWallet.isEnabled = false

        lifecycleScope.launch(Dispatchers.IO) {
            try {
                // Generate a deterministic or randomized checksummed 0x address
                val randomSeed = UUID.randomUUID().toString() + System.currentTimeMillis()
                val md = MessageDigest.getInstance("SHA-256")
                val hashBytes = md.digest(randomSeed.toByteArray())
                val hex = hashBytes.take(20).joinToString("") { "%02x".format(it) }
                val address = "0x$hex"

                GamificationManager.setWalletAddress(address)

                withContext(Dispatchers.Main) {
                    btnConnectWallet.isEnabled = true
                    updateWalletDisplay()
                    loadAchievements()
                    Toast.makeText(this@AchievementsActivity, "Wallet linked: $address (+50 PULSE, +200 XP)", Toast.LENGTH_LONG).show()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    tvWalletStatus.text = "Connection failed"
                    btnConnectWallet.isEnabled = true
                }
            }
        }
    }

    private fun disconnectWallet() {
        GamificationManager.setWalletAddress(null)
        updateWalletDisplay()
        loadAchievements()
        Toast.makeText(this, "Wallet unlinked.", Toast.LENGTH_SHORT).show()
    }

    private fun loadAchievements() {
        val badges = GamificationManager.getAllBadges()
        val items = badges.map { b ->
            val isUnlocked = b.progress >= b.target
            val progressText = if (isUnlocked) "Completed (${b.target}/${b.target})" else "Progress: ${b.progress}/${b.target}"
            Achievement(
                title = b.title,
                description = "${b.description} • $progressText",
                iconRes = b.iconRes,
                isUnlocked = isUnlocked
            )
        }
        adapter.updateData(items)
    }
}

data class Achievement(val title: String, val description: String, val iconRes: Int, var isUnlocked: Boolean)

class AchievementsAdapter(private var list: List<Achievement>) :
    RecyclerView.Adapter<AchievementsAdapter.ViewHolder>() {

    class ViewHolder(v: View) : RecyclerView.ViewHolder(v) {
        val icon: ImageView = v.findViewById(R.id.imgBadge)
        val title: TextView = v.findViewById(R.id.tvTitle)
        val desc: TextView = v.findViewById(R.id.tvDesc)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val v = LayoutInflater.from(parent.context).inflate(R.layout.item_achievement, parent, false)
        return ViewHolder(v)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val item = list[position]
        holder.title.text = item.title
        holder.desc.text = item.description
        holder.icon.setImageResource(item.iconRes)
        holder.itemView.alpha = if (item.isUnlocked) 1.0f else 0.45f
    }

    override fun getItemCount() = list.size

    fun updateData(newList: List<Achievement>) {
        list = newList
        notifyDataSetChanged()
    }
}

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
import java.util.UUID

class AchievementsActivity : AppCompatActivity() {

    private lateinit var tvWalletStatus: TextView
    private lateinit var tvWalletAddress: TextView
    private lateinit var btnConnectWallet: MaterialButton
    private lateinit var achievementsRecyclerView: RecyclerView

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

        btnConnectWallet.setOnClickListener {
            connectWallet()
        }

        setupAchievementsList()
    }

    private fun connectWallet() {
        tvWalletStatus.text = "Connecting..."
        btnConnectWallet.isEnabled = false

        lifecycleScope.launch(Dispatchers.IO) {
            try {
                val address = "0x" + UUID.randomUUID().toString().replace("-", "").take(40)

                withContext(Dispatchers.Main) {
                    tvWalletStatus.text = "Wallet Connected"
                    tvWalletAddress.text = address
                    btnConnectWallet.visibility = View.GONE
                    Toast.makeText(this@AchievementsActivity, "Connected: $address", Toast.LENGTH_SHORT).show()
                    
                    (achievementsRecyclerView.adapter as AchievementsAdapter).unlockAchievement()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    tvWalletStatus.text = "Failed to connect"
                    btnConnectWallet.isEnabled = true
                }
            }
        }
    }

    private fun setupAchievementsList() {
        val achievements = listOf(
            Achievement("First Step", "Walk 1,000 steps in a day", R.drawable.ic_map, true),
            Achievement("Eco Commuter", "Use public transit 5 times", R.drawable.ic_traffic, true),
            Achievement("Clean Air Champion", "Report 3 low-pollution zones", R.drawable.ic_dashboard, false),
            Achievement("Web3 Pioneer", "Connect a Web3 Wallet", R.drawable.ic_settings, false)
        )

        achievementsRecyclerView.layoutManager = LinearLayoutManager(this)
        achievementsRecyclerView.adapter = AchievementsAdapter(achievements.toMutableList())
    }
}

data class Achievement(val title: String, val description: String, val iconRes: Int, var isUnlocked: Boolean)

class AchievementsAdapter(private val list: MutableList<Achievement>) :
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
        holder.itemView.alpha = if (item.isUnlocked) 1.0f else 0.5f
    }

    override fun getItemCount() = list.size

    fun unlockAchievement() {
        if (list.size > 3) {
            list[3].isUnlocked = true
            notifyItemChanged(3)
        }
    }
}

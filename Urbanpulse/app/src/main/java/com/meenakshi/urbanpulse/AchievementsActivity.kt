package com.meenakshi.urbanpulse

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
import org.web3j.crypto.Keys
import org.web3j.protocol.Web3j
import org.web3j.protocol.http.HttpService
import java.math.BigInteger

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
                // Simulate Wallet Connection by generating a new key pair (or connecting to node)
                // In a real app, you'd use WalletConnect to link MetaMask
                
                // Connect to a public node (e.g., Cloudflare Eth Mainnet for read-only check)
                // val web3 = Web3j.build(HttpService("https://cloudflare-eth.com"))
                // val clientVersion = web3.web3ClientVersion().send()
                
                // Create a dummy wallet for demo
                val ecKeyPair = Keys.createEcKeyPair()
                val address = "0x" + Keys.getAddress(ecKeyPair)

                withContext(Dispatchers.Main) {
                    tvWalletStatus.text = "Wallet Connected"
                    tvWalletAddress.text = address
                    btnConnectWallet.visibility = View.GONE
                    Toast.makeText(this@AchievementsActivity, "Connected: $address", Toast.LENGTH_SHORT).show()
                    
                    // Reveal hidden achievements or update status
                    (achievementsRecyclerView.adapter as AchievementsAdapter).unlockAchievement()
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    tvWalletStatus.text = "Connection Failed"
                    btnConnectWallet.isEnabled = true
                    Toast.makeText(this@AchievementsActivity, "Error: ${e.message}", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }

    private fun setupAchievementsList() {
        val list = mutableListOf(
            Achievement("Carbon Cutter", "Saved 50kg of CO2 emissions", true),
            Achievement("Public Transport Hero", "Used public transport 20 times", true),
            Achievement("Early Adopter", "Joined UrbanPulse Alpha", true),
            Achievement("Green Investor", "Owned 1 Green NFT (Hidden)", false) // Locked initially
        )
        
        achievementsRecyclerView.layoutManager = LinearLayoutManager(this)
        achievementsRecyclerView.adapter = AchievementsAdapter(list)
    }
}

data class Achievement(val title: String, val desc: String, var isUnlocked: Boolean)

class AchievementsAdapter(private val items: List<Achievement>) : RecyclerView.Adapter<AchievementsAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val title: TextView = view.findViewById(R.id.tvTitle)
        val desc: TextView = view.findViewById(R.id.tvDesc)
        val badge: ImageView = view.findViewById(R.id.imgBadge)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_achievement, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val item = items[position]
        holder.title.text = item.title
        holder.desc.text = item.desc
        
        if (item.isUnlocked) {
            holder.badge.alpha = 1.0f
            holder.title.alpha = 1.0f
        } else {
            holder.badge.alpha = 0.3f
            holder.title.alpha = 0.5f
            holder.desc.text = "Connect Wallet to unlock"
        }
    }

    override fun getItemCount() = items.size
    
    fun unlockAchievement() {
        // Demo logic: Unlock the last item
        if (items.isNotEmpty()) {
            items.last().isUnlocked = true
            notifyItemChanged(items.lastIndex)
        }
    }
}

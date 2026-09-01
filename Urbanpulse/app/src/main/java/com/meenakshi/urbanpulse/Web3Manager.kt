package com.meenakshi.urbanpulse

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

object Web3Manager {

    private const val ADDR_PULSE_TOKEN = "0x5fbdb2315678afecb367f032d93f642f64180aa3"

    fun loadOrCreateWallet(context: Context): String {
        val prefs = context.getSharedPreferences("web3_wallet", Context.MODE_PRIVATE)
        var address = prefs.getString("wallet_address", null)
        if (address == null) {
            address = "0x" + java.util.UUID.randomUUID().toString().replace("-", "").take(40)
            prefs.edit().putString("wallet_address", address).apply()
        }
        return address
    }

    suspend fun getPulseBalance(): String = withContext(Dispatchers.IO) {
        "1240"
    }

    suspend fun claimReward(taskId: String): String = withContext(Dispatchers.IO) {
        "0x" + java.util.UUID.randomUUID().toString().replace("-", "")
    }
}

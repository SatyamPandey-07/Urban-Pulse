package com.meenakshi.urbanpulse

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.web3j.abi.FunctionEncoder
import org.web3j.abi.FunctionReturnDecoder
import org.web3j.abi.TypeReference
import org.web3j.abi.datatypes.Address
import org.web3j.abi.datatypes.Function
import org.web3j.abi.datatypes.Type
import org.web3j.abi.datatypes.Utf8String
import org.web3j.abi.datatypes.generated.Uint256
import org.web3j.crypto.Credentials
import org.web3j.crypto.ECKeyPair
import org.web3j.crypto.Keys
import org.web3j.crypto.RawTransaction
import org.web3j.crypto.TransactionEncoder
import org.web3j.protocol.Web3j
import org.web3j.protocol.core.DefaultBlockParameterName
import org.web3j.protocol.http.HttpService
import org.web3j.utils.Numeric
import java.math.BigInteger

object Web3Manager {
    // Emulator localhost: 10.0.2.2. For physical device use your PC's IP (e.g. 192.168.x.x)
    private const val RPC_URL = "http://10.0.2.2:8545" 
    private const val CHAIN_ID = 31337L

    // Contract Addresses (from documentation)
    private const val ADDR_PULSE_TOKEN = "0x5fbdb2315678afecb367f032d93f642f64180aa3"
    private const val ADDR_PROFILE = "0xe7f1725E7734CE288f8367e1Bb143E90bb3F0512"
    private const val ADDR_NFT = "0x9fE46736679D2D9a65F0992F2272dE9f3c7fa6e0"
    private const val ADDR_STAKING = "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9"
    private const val ADDR_REWARDS = "0x71cB05EE1b1b1b979bB1b4bD0aB2d8fC3b1b4b4b4"

    private val web3j: Web3j = Web3j.build(HttpService(RPC_URL))
    var credentials: Credentials? = null

    // Wallet Persistence
    fun loadOrCreateWallet(context: Context): String {
        val prefs = context.getSharedPreferences("web3_wallet", Context.MODE_PRIVATE)
        val privateKey = prefs.getString("private_key", null)

        if (privateKey != null) {
            credentials = Credentials.create(privateKey)
        } else {
            val ecKeyPair = Keys.createEcKeyPair()
            val newPrivateKey = Numeric.toHexStringNoPrefix(ecKeyPair.privateKey)
            prefs.edit().putString("private_key", newPrivateKey).apply()
            credentials = Credentials.create(newPrivateKey)
        }
        return credentials?.address ?: ""
    }

    suspend fun getPulseBalance(): String = withContext(Dispatchers.IO) {
        if (credentials == null) return@withContext "0"
        
        // balanceOf(address) -> uint256
        val function = Function(
            "balanceOf",
            listOf(Address(credentials!!.address)),
            listOf(object : TypeReference<Uint256>() {})
        )
        val encoded = FunctionEncoder.encode(function)
        
        try {
            val response = web3j.ethCall(
                org.web3j.protocol.core.methods.request.Transaction.createEthCallTransaction(
                    credentials!!.address, ADDR_PULSE_TOKEN, encoded
                ),
                DefaultBlockParameterName.LATEST
            ).send()
            
            val result = FunctionReturnDecoder.decode(response.value, function.outputParameters)
            if (result.isNotEmpty()) {
                val balanceWei = result[0].value as BigInteger
                // Convert Wei to Ether (18 decimals)
                // Simple conversion: / 1e18
                val balance = balanceWei.divide(BigInteger("1000000000000000000"))
                return@withContext balance.toString()
            }
        } catch (e: Exception) {
            Log.e("Web3", "Error fetching balance", e)
        }
        "0"
    }

    suspend fun claimReward(taskId: String): String = withContext(Dispatchers.IO) {
        if (credentials == null) throw Exception("Wallet not connected")

        val function = Function(
            "claimReward",
            listOf(Utf8String(taskId)),
            emptyList()
        )
        val encodedFunction = FunctionEncoder.encode(function)

        sendTransaction(ADDR_REWARDS, encodedFunction)
    }

    private fun sendTransaction(contractAddress: String, data: String): String {
        val ethGetTransactionCount = web3j.ethGetTransactionCount(
            credentials!!.address, DefaultBlockParameterName.LATEST
        ).send()
        val nonce = ethGetTransactionCount.transactionCount

        // Gas settings (Hardcoded for local testnet, dynamic is better)
        val gasPrice = web3j.ethGasPrice().send().gasPrice
        val gasLimit = BigInteger.valueOf(500_000)

        val rawTransaction = RawTransaction.createTransaction(
            nonce, gasPrice, gasLimit, contractAddress, data
        )

        val signedMessage = TransactionEncoder.signMessage(rawTransaction, CHAIN_ID, credentials)
        val hexValue = Numeric.toHexString(signedMessage)

        val ethSendTransaction = web3j.ethSendRawTransaction(hexValue).send()
        
        if (ethSendTransaction.hasError()) {
            throw Exception(ethSendTransaction.error.message)
        }
        return ethSendTransaction.transactionHash
    }
}

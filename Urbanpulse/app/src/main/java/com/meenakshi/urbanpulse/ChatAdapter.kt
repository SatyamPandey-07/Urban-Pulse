package com.meenakshi.urbanpulse

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class ChatAdapter(private val messages: MutableList<ChatMessage>) :
    RecyclerView.Adapter<ChatAdapter.ChatViewHolder>() {

    class ChatViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val aiMessageLayout: View = itemView.findViewById(R.id.aiMessageLayout)
        val aiMessageText: TextView = itemView.findViewById(R.id.aiMessageText)
        val userMessageText: TextView = itemView.findViewById(R.id.userMessageText)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ChatViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_chat_message, parent, false)
        return ChatViewHolder(view)
    }

    override fun onBindViewHolder(holder: ChatViewHolder, position: Int) {
        val message = messages[position]

        if (message.isUser) {
            holder.aiMessageLayout.visibility = View.GONE
            holder.userMessageText.visibility = View.VISIBLE
            holder.userMessageText.text = message.message
        } else {
            holder.aiMessageLayout.visibility = View.VISIBLE
            holder.userMessageText.visibility = View.GONE
            holder.aiMessageText.text = message.message
        }
    }

    override fun getItemCount(): Int = messages.size

    fun addMessage(message: ChatMessage) {
        messages.add(message)
        notifyItemInserted(messages.size - 1)
    }
}

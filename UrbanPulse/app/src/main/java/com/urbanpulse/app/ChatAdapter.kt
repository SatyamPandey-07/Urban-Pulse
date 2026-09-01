package com.urbanpulse.app

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class ChatAdapter(private val messages: MutableList<ChatMessage>) :
    RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    companion object {
        private const val VIEW_TYPE_USER = 1
        private const val VIEW_TYPE_AI = 2
        private const val VIEW_TYPE_TYPING = 3
    }

    class ChatViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val aiMessageLayout: View = itemView.findViewById(R.id.aiMessageLayout)
        val aiMessageText: TextView = itemView.findViewById(R.id.aiMessageText)
        val userMessageText: TextView = itemView.findViewById(R.id.userMessageText)
    }

    class TypingViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView)

    override fun getItemViewType(position: Int): Int {
        val msg = messages[position]
        return when {
            msg.isLoading -> VIEW_TYPE_TYPING
            msg.isUser -> VIEW_TYPE_USER
            else -> VIEW_TYPE_AI
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        return if (viewType == VIEW_TYPE_TYPING) {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_typing_indicator, parent, false)
            TypingViewHolder(view)
        } else {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_chat_message, parent, false)
            ChatViewHolder(view)
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        if (holder is ChatViewHolder) {
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
    }

    override fun getItemCount(): Int = messages.size

    fun addMessage(message: ChatMessage) {
        messages.add(message)
        notifyItemInserted(messages.size - 1)
    }

    fun showTypingIndicator() {
        if (messages.none { it.isLoading }) {
            messages.add(ChatMessage("", isUser = false, isLoading = true))
            notifyItemInserted(messages.size - 1)
        }
    }

    fun removeTypingIndicator() {
        val index = messages.indexOfFirst { it.isLoading }
        if (index != -1) {
            messages.removeAt(index)
            notifyItemRemoved(index)
        }
    }
}

package com.urbanpulse.app

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.HorizontalScrollView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup

class ChatAdapter(
    private val messages: MutableList<ChatMessage>,
    private val onMcqOptionSelected: ((String) -> Unit)? = null,
    private val onSaveTripClicked: ((TripPlan) -> Unit)? = null,
    private val onViewTripClicked: ((TripPlan) -> Unit)? = null
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    companion object {
        private const val VIEW_TYPE_USER = 1
        private const val VIEW_TYPE_AI = 2
        private const val VIEW_TYPE_TYPING = 3
    }

    class ChatViewHolder(itemView: View) : RecyclerView.ViewHolder(itemView) {
        val aiMessageLayout: View = itemView.findViewById(R.id.aiMessageLayout)
        val aiMessageText: TextView = itemView.findViewById(R.id.aiMessageText)
        val userMessageText: TextView = itemView.findViewById(R.id.userMessageText)
        val mcqContainer: HorizontalScrollView = itemView.findViewById(R.id.mcqContainer)
        val chipGroupMcq: ChipGroup = itemView.findViewById(R.id.chipGroupMcq)
        val cardTripPreview: MaterialCardView = itemView.findViewById(R.id.cardTripPreview)
        val tvTripCardTitle: TextView = itemView.findViewById(R.id.tvTripCardTitle)
        val tvTripCardCo2: TextView = itemView.findViewById(R.id.tvTripCardCo2)
        val tvTripCardDetails: TextView = itemView.findViewById(R.id.tvTripCardDetails)
        val btnSaveTrip: MaterialButton = itemView.findViewById(R.id.btnSaveTrip)
        val btnViewItinerary: MaterialButton = itemView.findViewById(R.id.btnViewItinerary)
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

                // Bind MCQ Chips
                if (message.mcqQuestion != null && message.mcqQuestion.options.isNotEmpty()) {
                    holder.mcqContainer.visibility = View.VISIBLE
                    holder.chipGroupMcq.removeAllViews()
                    for (option in message.mcqQuestion.options) {
                        val chip = LayoutInflater.from(holder.itemView.context)
                            .inflate(R.layout.item_filter_chip, holder.chipGroupMcq, false) as Chip
                        chip.text = option
                        chip.isCheckable = false
                        chip.setOnClickListener {
                            onMcqOptionSelected?.invoke(option)
                        }
                        holder.chipGroupMcq.addView(chip)
                    }
                } else {
                    holder.mcqContainer.visibility = View.GONE
                }

                // Bind Generated Trip Preview Card
                if (message.generatedTrip != null) {
                    val trip = message.generatedTrip
                    holder.cardTripPreview.visibility = View.VISIBLE
                    holder.tvTripCardTitle.text = trip.title
                    holder.tvTripCardCo2.text = "-${trip.co2SavedKg} kg CO2"
                    holder.tvTripCardDetails.text = "🚆 ${trip.travelMode} • 🏨 ${trip.hotelName} • 💰 ₹${trip.totalBudgetInr}"
                    holder.btnSaveTrip.setOnClickListener {
                        onSaveTripClicked?.invoke(trip)
                    }
                    holder.btnViewItinerary.setOnClickListener {
                        onViewTripClicked?.invoke(trip)
                    }
                } else {
                    holder.cardTripPreview.visibility = View.GONE
                }
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

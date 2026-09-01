package com.urbanpulse.app

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.tomtom.sdk.common.functional.rightIfNotNull
import com.tomtom.sdk.search.model.result.SearchResult

class SearchAdapter(
    private val items: List<SearchResult>,
    private val onClick: (SearchResult) -> Unit
) : RecyclerView.Adapter<SearchAdapter.Holder>() {

    inner class Holder(view: View) : RecyclerView.ViewHolder(view) {
        val text = view.findViewById<TextView>(R.id.searchItemText)

        fun bind(result: SearchResult) {
            text.text = result.place.address?.freeformAddress
                ?: result.place.name

            itemView.setOnClickListener { onClick(result) }
        }
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_search_result, parent, false)
        return Holder(view)
    }

    private var itemsList = items.toMutableList()

    fun updateResults(newItems: List<SearchResult>) {
        itemsList.clear()
        itemsList.addAll(newItems)
        notifyDataSetChanged()
    }

    override fun getItemCount() = itemsList.size

    override fun onBindViewHolder(holder: Holder, position: Int) =
        holder.bind(itemsList[position])
}

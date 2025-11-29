package com.meenakshi.urbanpulse

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView

class BadgesFragment : Fragment() {
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View? {
        val view = inflater.inflate(R.layout.fragment_badges, container, false)
        val recyclerView = view.findViewById<RecyclerView>(R.id.recyclerView)
        recyclerView.layoutManager = GridLayoutManager(context, 3) // 3 columns
        recyclerView.adapter = BadgesAdapter(GamificationManager.getAllBadges())
        return view
    }
}

class BadgesAdapter(private val badges: List<Badge>) : RecyclerView.Adapter<BadgesAdapter.ViewHolder>() {
    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val icon: ImageView = view.findViewById(R.id.imgBadge)
        val title: TextView = view.findViewById(R.id.tvBadgeTitle)
        val progress: TextView = view.findViewById(R.id.tvBadgeProgress)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_badge, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val badge = badges[position]
        holder.icon.setImageResource(badge.iconRes)
        holder.title.text = badge.title
        
        val isUnlocked = badge.progress >= badge.target
        holder.itemView.alpha = if (isUnlocked) 1.0f else 0.4f
        
        if (!isUnlocked) {
            holder.progress.visibility = View.VISIBLE
            holder.progress.text = "${badge.progress}/${badge.target}"
        } else {
            holder.progress.visibility = View.GONE
        }
    }

    override fun getItemCount() = badges.size
}

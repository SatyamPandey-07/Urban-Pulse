package com.urbanpulse.app

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.progressindicator.LinearProgressIndicator

class ChallengesFragment : Fragment() {
    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View? {
        val view = inflater.inflate(R.layout.fragment_challenges, container, false)
        val recyclerView = view.findViewById<RecyclerView>(R.id.recyclerView)
        recyclerView.layoutManager = LinearLayoutManager(context)
        recyclerView.adapter = ChallengesAdapter(GamificationManager.getAvailableChallenges())
        return view
    }
}

class ChallengesAdapter(private val challenges: List<Challenge>) : RecyclerView.Adapter<ChallengesAdapter.ViewHolder>() {
    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val type: TextView = view.findViewById(R.id.tvChallengeType)
        val title: TextView = view.findViewById(R.id.tvChallengeTitle)
        val reward: TextView = view.findViewById(R.id.tvReward)
        val progress: LinearProgressIndicator = view.findViewById(R.id.progressChallenge)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_challenge, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val challenge = challenges[position]
        holder.type.text = challenge.type.uppercase()
        holder.title.text = challenge.title
        holder.reward.text = "+${challenge.xpReward} XP • +${challenge.pulseReward} PULSE"
        holder.progress.max = challenge.target
        holder.progress.progress = challenge.progress
    }

    override fun getItemCount() = challenges.size
}

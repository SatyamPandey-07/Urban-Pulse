package com.meenakshi.urbanpulse

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.button.MaterialButton
import com.meenakshi.urbanpulse.evidence.RankedHospitalityStay

class HospitalityAdapter(
    private var rankedStays: List<RankedHospitalityStay>,
    private val onItemClick: (RankedHospitalityStay) -> Unit
) : RecyclerView.Adapter<HospitalityAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val tvStayName: TextView = view.findViewById(R.id.tvStayName)
        val tvStayCategoryLocation: TextView = view.findViewById(R.id.tvStayCategoryLocation)
        val tvEcoBadge: TextView = view.findViewById(R.id.tvEcoBadge)
        val tvBadges: TextView = view.findViewById(R.id.tvBadges)
        val tvEnergyWaste: TextView = view.findViewById(R.id.tvEnergyWaste)
        val tvCarbonImpact: TextView = view.findViewById(R.id.tvCarbonImpact)
        val tvAccessibilityTags: TextView = view.findViewById(R.id.tvAccessibilityTags)
        val tvPrice: TextView = view.findViewById(R.id.tvPrice)
        val tvAccessibilityScore: TextView = view.findViewById(R.id.tvAccessibilityScore)
        val btnViewAudit: MaterialButton = view.findViewById(R.id.btnViewAudit)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_hospitality_stay, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val ranked = rankedStays[position]
        val stay = ranked.stay
        holder.tvStayName.text = stay.name
        holder.tvStayCategoryLocation.text = "${stay.category} • ${stay.location}"
        holder.tvEcoBadge.text = "Eco Level ${stay.ecoScore}"
        holder.tvEnergyWaste.text = "${stay.energySource} • ${stay.wastePolicy}"
        holder.tvCarbonImpact.text = stay.carbonFootprintPerNight
        holder.tvAccessibilityTags.text = "Accessibility: " + stay.accessibilityTags.joinToString(" • ")
        holder.tvPrice.text = stay.pricePerNight
        holder.tvAccessibilityScore.text = "${stay.accessibilityRating}% Accessibility Match"

        if (ranked.badges.isNotEmpty()) {
            holder.tvBadges.visibility = View.VISIBLE
            holder.tvBadges.text = "🏆 " + ranked.badges.joinToString("  •  ") { it.label }
        } else {
            holder.tvBadges.visibility = View.GONE
        }

        holder.btnViewAudit.setOnClickListener { onItemClick(ranked) }
        holder.itemView.setOnClickListener { onItemClick(ranked) }
    }

    override fun getItemCount(): Int = rankedStays.size

    fun updateList(newList: List<RankedHospitalityStay>) {
        rankedStays = newList
        notifyDataSetChanged()
    }
}

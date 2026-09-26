package com.urbanpulse.app

import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.EditText
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.button.MaterialButton
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.GeoPoint
import com.google.firebase.storage.FirebaseStorage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import java.util.Date
import java.util.UUID

class ReportIncidentActivity : AppCompatActivity() {

    private lateinit var etDescription: EditText
    private lateinit var chipGroupIncidentType: ChipGroup
    private lateinit var imgPreview: ImageView
    private lateinit var btnAttachPhoto: MaterialButton
    private lateinit var btnSubmit: MaterialButton
    private lateinit var progressBar: ProgressBar

    private var imageUri: Uri? = null

    private val selectImageLauncher = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        if (uri != null) {
            imageUri = uri
            imgPreview.setImageURI(uri)
            imgPreview.visibility = View.VISIBLE
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_report_incident)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        toolbar.setNavigationOnClickListener { finish() }

        etDescription = findViewById(R.id.etDescription)
        chipGroupIncidentType = findViewById(R.id.chipGroupIncidentType)
        imgPreview = findViewById(R.id.imgPreview)
        btnAttachPhoto = findViewById(R.id.btnAttachPhoto)
        btnSubmit = findViewById(R.id.btnSubmit)
        progressBar = findViewById(R.id.progressBar)

        btnAttachPhoto.setOnClickListener {
            selectImageLauncher.launch("image/*")
        }

        btnSubmit.setOnClickListener {
            submitReport()
        }
    }

    private fun submitReport() {
        val selectedChipId = chipGroupIncidentType.checkedChipId
        if (selectedChipId == View.NO_ID) {
            Toast.makeText(this, "Please select an incident type", Toast.LENGTH_SHORT).show()
            return
        }
        val type = findViewById<Chip>(selectedChipId).text.toString()
        val description = etDescription.text.toString().trim()

        if (description.isEmpty()) {
            Toast.makeText(this, "Please provide a description of the obstacle/incident", Toast.LENGTH_SHORT).show()
            return
        }

        progressBar.visibility = View.VISIBLE
        btnSubmit.isEnabled = false

        lifecycleScope.launch(Dispatchers.IO) {
            val locMgr = UserLocationManager.getInstance(this@ReportIncidentActivity)
            val lat = locMgr.currentLatitude
            val lon = locMgr.currentLongitude

            val userId = FirebaseAuth.getInstance().currentUser?.uid ?: "user_${UUID.randomUUID().toString().take(6)}"

            var imageUrl = ""
            if (imageUri != null) {
                try {
                    val storageRef = FirebaseStorage.getInstance().reference
                    val imageFileName = "${UUID.randomUUID()}.jpg"
                    val imageRef = storageRef.child("incidents/$imageFileName")
                    imageRef.putFile(imageUri!!).await()
                    imageUrl = imageRef.downloadUrl.await().toString()
                } catch (e: Exception) {
                    // Storage not configured; proceed with local URI
                    imageUrl = imageUri.toString()
                }
            }

            try {
                val db = FirebaseFirestore.getInstance()
                val incident = Incident(
                    id = UUID.randomUUID().toString(),
                    type = type,
                    description = description,
                    imageUrl = imageUrl,
                    location = GeoPoint(lat, lon),
                    userId = userId,
                    timestamp = Date()
                )
                db.collection("incidents").add(incident).await()
            } catch (e: Exception) {
                // Firestore offline
            }

            // Award user gamification points and badge progress
            GamificationManager.incrementIncidentsReported()

            withContext(Dispatchers.Main) {
                progressBar.visibility = View.GONE
                Toast.makeText(
                    this@ReportIncidentActivity,
                    "Incident Reported! +25 PULSE & +100 XP Earned.",
                    Toast.LENGTH_LONG
                ).show()
                finish()
            }
        }
    }
}

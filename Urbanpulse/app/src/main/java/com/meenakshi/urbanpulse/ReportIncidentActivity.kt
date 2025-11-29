package com.meenakshi.urbanpulse

import android.Manifest
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.EditText
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.lifecycle.lifecycleScope
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.button.MaterialButton
import com.google.android.material.chip.Chip
import com.google.android.material.chip.ChipGroup
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.GeoPoint
import com.google.firebase.storage.FirebaseStorage
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
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
    
    private val locationPermissionRequest = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        if (permissions.getOrDefault(Manifest.permission.ACCESS_FINE_LOCATION, false)) {
            submitReport()
        } else {
            Toast.makeText(this, "Location permission is required to report an incident", Toast.LENGTH_LONG).show()
            progressBar.visibility = View.GONE
            btnSubmit.isEnabled = true
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
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                locationPermissionRequest.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION))
            } else {
                submitReport()
            }
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
        val userId = FirebaseAuth.getInstance().currentUser?.uid

        if (description.isEmpty() || imageUri == null || userId == null) {
            Toast.makeText(this, "Please provide a description and attach a photo.", Toast.LENGTH_SHORT).show()
            return
        }

        progressBar.visibility = View.VISIBLE
        btnSubmit.isEnabled = false

        lifecycleScope.launch {
            try {
                // Get Location
                val locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
                val location = if (ActivityCompat.checkSelfPermission(this@ReportIncidentActivity, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                     locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                } else null
                
                if (location == null) {
                    Toast.makeText(this@ReportIncidentActivity, "Could not get location. Please try again.", Toast.LENGTH_SHORT).show()
                    progressBar.visibility = View.GONE
                    btnSubmit.isEnabled = true
                    return@launch
                }
                
                val geoPoint = GeoPoint(location.latitude, location.longitude)

                // Upload Image
                val storageRef = FirebaseStorage.getInstance().reference
                val imageFileName = "${UUID.randomUUID()}.jpg"
                val imageRef = storageRef.child("incidents/$imageFileName")
                imageRef.putFile(imageUri!!).await()
                val imageUrl = imageRef.downloadUrl.await().toString()
                
                // Save to Firestore
                val db = FirebaseFirestore.getInstance()
                val incident = Incident(
                    type = type,
                    description = description,
                    imageUrl = imageUrl,
                    location = geoPoint,
                    userId = userId
                )
                db.collection("incidents").add(incident).await()
                
                Toast.makeText(this@ReportIncidentActivity, "Incident Reported Successfully", Toast.LENGTH_LONG).show()
                finish()
            } catch (e: Exception) {
                progressBar.visibility = View.GONE
                btnSubmit.isEnabled = true
                Toast.makeText(this@ReportIncidentActivity, "Error: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }
}

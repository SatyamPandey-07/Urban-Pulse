package com.urbanpulse.app

import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.EditText
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.button.MaterialButton
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.storage.FirebaseStorage
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import java.util.UUID

class CreatePostActivity : AppCompatActivity() {

    private lateinit var etPostContent: EditText
    private lateinit var imgPreview: ImageView
    private lateinit var btnAddImage: ImageButton
    private lateinit var btnPost: MaterialButton
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
        setContentView(R.layout.activity_create_post)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        toolbar.setNavigationOnClickListener { finish() }

        etPostContent = findViewById(R.id.etPostContent)
        imgPreview = findViewById(R.id.imgPreview)
        btnAddImage = findViewById(R.id.btnAddImage)
        btnPost = findViewById(R.id.btnPost)
        progressBar = findViewById(R.id.progressBar)

        btnAddImage.setOnClickListener {
            selectImageLauncher.launch("image/*")
        }
        
        btnPost.setOnClickListener {
            createPost()
        }
    }

    private fun createPost() {
        val text = etPostContent.text.toString().trim()
        val user = FirebaseAuth.getInstance().currentUser

        if (text.isEmpty() && imageUri == null) {
            Toast.makeText(this, "Cannot create an empty post", Toast.LENGTH_SHORT).show()
            return
        }
        if (user == null) {
            Toast.makeText(this, "You must be logged in to post", Toast.LENGTH_SHORT).show()
            return
        }

        progressBar.visibility = View.VISIBLE
        btnPost.isEnabled = false

        lifecycleScope.launch {
            try {
                var imageUrl: String? = null
                if (imageUri != null) {
                    val storageRef = FirebaseStorage.getInstance().reference
                    val imageFileName = "${UUID.randomUUID()}.jpg"
                    val imageRef = storageRef.child("community_posts/$imageFileName")
                    imageRef.putFile(imageUri!!).await()
                    imageUrl = imageRef.downloadUrl.await().toString()
                }

                val db = FirebaseFirestore.getInstance()
                val post = CommunityPost(
                    text = text,
                    imageUrl = imageUrl,
                    userId = user.uid,
                    userName = user.displayName ?: "User",
                    userAvatarUrl = user.photoUrl?.toString()
                )
                db.collection("community_posts").add(post).await()
                
                Toast.makeText(this@CreatePostActivity, "Post created!", Toast.LENGTH_SHORT).show()
                finish()

            } catch (e: Exception) {
                progressBar.visibility = View.GONE
                btnPost.isEnabled = true
                Toast.makeText(this@CreatePostActivity, "Error creating post: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }
}

package com.urbanpulse.app

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import coil.load
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query

class CommunityActivity : AppCompatActivity() {

    private lateinit var recyclerView: RecyclerView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_community)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        toolbar.setNavigationOnClickListener { finish() }
        
        toolbar.setOnMenuItemClickListener {
            if (it.itemId == R.id.action_create_post) {
                startActivity(Intent(this, CreatePostActivity::class.java))
                true
            } else false
        }
        
        findViewById<FloatingActionButton>(R.id.fabCreatePost).setOnClickListener {
            startActivity(Intent(this, CreatePostActivity::class.java))
        }

        recyclerView = findViewById(R.id.recyclerView)
        recyclerView.layoutManager = LinearLayoutManager(this)

        fetchPosts()
    }
    
    private fun fetchPosts() {
        FirebaseFirestore.getInstance().collection("community_posts")
            .orderBy("timestamp", Query.Direction.DESCENDING)
            .limit(20)
            .get()
            .addOnSuccessListener { snapshot ->
                val posts = snapshot.toObjects(CommunityPost::class.java)
                recyclerView.adapter = CommunityAdapter(posts)
            }
            .addOnFailureListener {
                Toast.makeText(this, "Failed to load posts: ${it.message}", Toast.LENGTH_SHORT).show()
            }
    }
}

class CommunityAdapter(private val posts: List<CommunityPost>) : RecyclerView.Adapter<CommunityAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val avatar: ImageView = view.findViewById(R.id.imgAvatar)
        val userName: TextView = view.findViewById(R.id.tvUserName)
        val timestamp: TextView = view.findViewById(R.id.tvTimestamp)
        val postText: TextView = view.findViewById(R.id.tvPostText)
        val postImage: ImageView = view.findViewById(R.id.imgPost)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_community_post, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val post = posts[position]
        
        holder.userName.text = post.userName
        holder.postText.text = post.text
        
        post.userAvatarUrl?.let { holder.avatar.load(it) }
        
        if (post.imageUrl != null) {
            holder.postImage.visibility = View.VISIBLE
            holder.postImage.load(post.imageUrl)
        } else {
            holder.postImage.visibility = View.GONE
        }
    }

    override fun getItemCount() = posts.size
}

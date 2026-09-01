package com.urbanpulse.app

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import coil.load
import com.google.android.material.appbar.MaterialToolbar
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.toObject

class PostDetailActivity : AppCompatActivity() {

    private lateinit var postId: String
    private lateinit var recyclerView: RecyclerView
    private lateinit var etComment: EditText
    private lateinit var btnSendComment: Button
    private lateinit var adapter: PostDetailAdapter

    private var post: CommunityPost? = null
    private val comments = mutableListOf<Comment>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_post_detail)

        postId = intent.getStringExtra("POST_ID") ?: run {
            finish()
            return
        }

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        toolbar.setNavigationOnClickListener { finish() }

        recyclerView = findViewById(R.id.recyclerView)
        etComment = findViewById(R.id.etComment)
        btnSendComment = findViewById(R.id.btnSendComment)
        
        setupRecyclerView()
        loadPostAndComments()
        
        btnSendComment.setOnClickListener {
            addComment()
        }
    }

    private fun setupRecyclerView() {
        adapter = PostDetailAdapter(post, comments)
        recyclerView.layoutManager = LinearLayoutManager(this)
        recyclerView.adapter = adapter
    }

    private fun loadPostAndComments() {
        val db = FirebaseFirestore.getInstance()
        
        // Load Post
        db.collection("community_posts").document(postId).get()
            .addOnSuccessListener { doc ->
                post = doc.toObject<CommunityPost>()?.copy(id = doc.id)
                adapter.post = post
                adapter.notifyItemChanged(0)
            }
            .addOnFailureListener {
                Toast.makeText(this, "Failed to load post", Toast.LENGTH_SHORT).show()
            }
            
        // Listen for comments
        db.collection("community_posts").document(postId).collection("comments")
            .orderBy("timestamp", Query.Direction.ASCENDING)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    return@addSnapshotListener
                }
                if (snapshot != null) {
                    comments.clear()
                    comments.addAll(snapshot.toObjects(Comment::class.java))
                    adapter.notifyDataSetChanged()
                }
            }
    }

    private fun addComment() {
        val text = etComment.text.toString().trim()
        val user = FirebaseAuth.getInstance().currentUser
        if (text.isEmpty() || user == null) return

        val comment = Comment(
            postId = postId,
            userId = user.uid,
            userName = user.displayName ?: "User",
            userAvatarUrl = user.photoUrl?.toString(),
            text = text
        )
        
        FirebaseFirestore.getInstance()
            .collection("community_posts").document(postId)
            .collection("comments").add(comment)
            .addOnSuccessListener {
                etComment.text.clear()
            }
            .addOnFailureListener {
                Toast.makeText(this, "Failed to add comment", Toast.LENGTH_SHORT).show()
            }
    }
}

class PostDetailAdapter(
    var post: CommunityPost?,
    private val comments: List<Comment>
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private val VIEW_TYPE_POST = 1
    private val VIEW_TYPE_COMMENT = 2

    // Post ViewHolder
    class PostViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val avatar: ImageView = view.findViewById(R.id.imgAvatar)
        val userName: TextView = view.findViewById(R.id.tvUserName)
        val timestamp: TextView = view.findViewById(R.id.tvTimestamp)
        val postText: TextView = view.findViewById(R.id.tvPostText)
        val postImage: ImageView = view.findViewById(R.id.imgPost)
    }
    
    // Comment ViewHolder
    class CommentViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val avatar: ImageView = view.findViewById(R.id.imgAvatar)
        val userName: TextView = view.findViewById(R.id.tvUserName)
        val commentText: TextView = view.findViewById(R.id.tvCommentText)
    }

    override fun getItemViewType(position: Int): Int {
        return if (position == 0) VIEW_TYPE_POST else VIEW_TYPE_COMMENT
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        return if (viewType == VIEW_TYPE_POST) {
            val view = LayoutInflater.from(parent.context).inflate(R.layout.item_community_post, parent, false)
            PostViewHolder(view)
        } else {
            val view = LayoutInflater.from(parent.context).inflate(R.layout.item_comment, parent, false)
            CommentViewHolder(view)
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        if (holder is PostViewHolder && post != null) {
            holder.userName.text = post!!.userName
            holder.postText.text = post!!.text
            post!!.userAvatarUrl?.let { holder.avatar.load(it) }
            if (post!!.imageUrl != null) {
                holder.postImage.visibility = View.VISIBLE
                holder.postImage.load(post!!.imageUrl)
            } else {
                holder.postImage.visibility = View.GONE
            }
        } else if (holder is CommentViewHolder) {
            val comment = comments[position - 1] // Adjust for post at position 0
            holder.userName.text = comment.userName
            holder.commentText.text = comment.text
            comment.userAvatarUrl?.let { holder.avatar.load(it) }
        }
    }

    override fun getItemCount(): Int = 1 + comments.size
}

package app.dominochain.mobile

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import app.dominochain.mobile.api.LeveragePhotoResponse
import app.dominochain.mobile.api.RetrofitClient
import app.dominochain.mobile.databinding.ActivityLeveragePhotosBinding
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream

class LeveragePhotosActivity : AppCompatActivity() {

    private lateinit var binding: ActivityLeveragePhotosBinding
    private val repository = LeveragePhotoRepository()
    private val adapter = LeveragePhotosAdapter { photo ->
        startActivity(Intent(this, LeveragePhotoDetailActivity::class.java).apply {
            putExtra(LeveragePhotoDetailActivity.EXTRA_PHOTO_ID, photo.id)
        })
    }

    private var pendingOriginal: File? = null
    private var pendingTeaser: File? = null
    private var uploadStep: Int = 0

    private val pickImage = registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        handlePickedImage(uri)
    }

    private fun handlePickedImage(uri: Uri?) {
        if (uri == null) return
        val file = copyToCache(uri)
        if (file == null) {
            Toast.makeText(this, R.string.leverage_pick_failed, Toast.LENGTH_SHORT).show()
            return
        }
        when (uploadStep) {
            1 -> {
                pendingOriginal = file
                uploadStep = 2
                binding.leverageStatus.setText(R.string.leverage_pick_teaser)
                Toast.makeText(this, R.string.leverage_pick_teaser, Toast.LENGTH_SHORT).show()
                pickImage.launch("image/*")
            }
            2 -> {
                pendingTeaser = file
                uploadStep = 3
                binding.leverageStatus.setText(R.string.leverage_pick_censored_optional)
                Toast.makeText(this, R.string.leverage_pick_censored_optional, Toast.LENGTH_LONG).show()
                uploadNow(censored = null)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        RetrofitClient.sessionManager = (application as BgApplication).sessionManager
        binding = ActivityLeveragePhotosBinding.inflate(layoutInflater)
        setContentView(binding.root)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        title = getString(R.string.leverage_photos_title)

        binding.leveragePhotosList.layoutManager = LinearLayoutManager(this)
        binding.leveragePhotosList.adapter = adapter
        binding.leverageUploadButton.setOnClickListener {
            uploadStep = 1
            pendingOriginal = null
            pendingTeaser = null
            binding.leverageStatus.setText(R.string.leverage_pick_original)
            pickImage.launch("image/*")
        }
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }

    private fun refresh() {
        binding.leverageStatus.setText(R.string.leverage_loading)
        lifecycleScope.launch {
            repository.list()
                .onSuccess {
                    adapter.submit(it.photos)
                    binding.leverageStatus.text = getString(R.string.leverage_count, it.photos.size)
                }
                .onFailure {
                    binding.leverageStatus.text = it.message
                }
        }
    }

    private fun uploadNow(censored: File?) {
        val original = pendingOriginal
        val teaser = pendingTeaser
        if (original == null || teaser == null) return
        binding.leverageUploadButton.isEnabled = false
        binding.leverageStatus.setText(R.string.leverage_uploading)
        lifecycleScope.launch {
            repository.create(original, teaser, censored)
                .onSuccess { photo ->
                    Toast.makeText(this@LeveragePhotosActivity, R.string.leverage_upload_success, Toast.LENGTH_SHORT).show()
                    startActivity(Intent(this@LeveragePhotosActivity, LeveragePhotoDetailActivity::class.java).apply {
                        putExtra(LeveragePhotoDetailActivity.EXTRA_PHOTO_ID, photo.id)
                    })
                    refresh()
                }
                .onFailure {
                    Toast.makeText(this@LeveragePhotosActivity, it.message, Toast.LENGTH_LONG).show()
                }
            binding.leverageUploadButton.isEnabled = true
            uploadStep = 0
        }
    }

    private fun copyToCache(uri: Uri): File? {
        return try {
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val ext = contentResolver.getType(uri)?.let { type ->
                when {
                    type.contains("png") -> ".png"
                    type.contains("webp") -> ".webp"
                    else -> ".jpg"
                }
            } ?: ".jpg"
            val file = File(cacheDir, "leverage_${System.currentTimeMillis()}$ext")
            FileOutputStream(file).use { output -> inputStream.copyTo(output) }
            file
        } catch (_: Exception) {
            null
        }
    }
}

private class LeveragePhotosAdapter(
    private val onClick: (LeveragePhotoResponse) -> Unit
) : RecyclerView.Adapter<LeveragePhotosAdapter.Holder>() {
    private var items: List<LeveragePhotoResponse> = emptyList()

    fun submit(photos: List<LeveragePhotoResponse>) {
        items = photos
        notifyDataSetChanged()
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
        val view = LayoutInflater.from(parent.context)
            .inflate(android.R.layout.simple_list_item_2, parent, false)
        return Holder(view)
    }

    override fun onBindViewHolder(holder: Holder, position: Int) {
        val item = items[position]
        holder.title.text = item.original_filename ?: "Photo #${item.id}"
        holder.subtitle.text = buildString {
            append(item.status)
            item.locked_until?.let { append(" · "); append(it) }
        }
        holder.itemView.setOnClickListener { onClick(item) }
    }

    override fun getItemCount(): Int = items.size

    class Holder(view: View) : RecyclerView.ViewHolder(view) {
        val title: TextView = view.findViewById(android.R.id.text1)
        val subtitle: TextView = view.findViewById(android.R.id.text2)
    }
}

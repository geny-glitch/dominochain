package com.bg

import com.bg.api.RetrofitClient
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.bg.api.TaskDetailResponse
import com.bg.databinding.ActivityTaskDetailBinding
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class TaskDetailActivity : AppCompatActivity() {

    private lateinit var binding: ActivityTaskDetailBinding
    private val repository = DeviceRepository()
    private var deviceId: String = ""
    private var taskId: Long = 0
    private var selectedMediaUri: Uri? = null
    private var selectedMediaFile: File? = null

    private val pickMedia = registerForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        uri?.let {
            selectedMediaUri = it
            selectedMediaFile = copyToCache(it)
            binding.proofMediaName.visibility = View.VISIBLE
            binding.proofMediaName.text = selectedMediaFile?.name ?: "Fichier sélectionné"
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        RetrofitClient.sessionManager = (application as BgApplication).sessionManager
        binding = ActivityTaskDetailBinding.inflate(layoutInflater)
        setContentView(binding.root)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        deviceId = intent.getStringExtra("device_id") ?: run {
            Toast.makeText(this, "Device ID manquant", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        taskId = intent.getLongExtra("task_id", 0)
        if (taskId == 0L) {
            Toast.makeText(this, "Task ID manquant", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        loadTaskDetail()

        binding.proofMediaButton.setOnClickListener {
            pickMedia.launch("image/*")
        }

        binding.proofSubmitButton.setOnClickListener {
            submitProof()
        }
    }

    private fun copyToCache(uri: Uri): File? {
        return try {
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val ext = contentResolver.getType(uri)?.let { type ->
                when {
                    type.contains("video") -> ".mp4"
                    type.contains("jpeg") || type.contains("jpg") -> ".jpg"
                    type.contains("png") -> ".png"
                    else -> ""
                }
            } ?: ".jpg"
            val file = File(cacheDir, "proof_${System.currentTimeMillis()}$ext")
            FileOutputStream(file).use { output ->
                inputStream.copyTo(output)
            }
            file
        } catch (e: Exception) {
            null
        }
    }

    private fun loadTaskDetail() {
        lifecycleScope.launch {
            val result = repository.getTaskDetail(deviceId, taskId)
            if (isDestroyed) return@launch
            result.onSuccess { task ->
                if (!isDestroyed) displayTask(task)
            }.onFailure {
                if (!isDestroyed) {
                    Toast.makeText(this@TaskDetailActivity, "Erreur: ${it.message}", Toast.LENGTH_SHORT).show()
                    finish()
                }
            }
        }
    }

    private fun displayTask(task: TaskDetailResponse) {
        binding.taskName.text = task.name
        binding.taskDeadline.text = "Deadline: ${formatDate(task.deadline_at)}"
        binding.taskStatus.text = task.status
        binding.taskDescription.text = task.description ?: "-"
        binding.taskExpectedProof.text = task.expected_proof ?: "-"

        if (task.can_submit_proof) {
            binding.proofFormSection.visibility = View.VISIBLE
            binding.proofSubmittedSection.visibility = View.GONE
        } else if (task.proof != null) {
            binding.proofFormSection.visibility = View.GONE
            binding.proofSubmittedSection.visibility = View.VISIBLE
            binding.proofSubmittedText.text = task.proof.text ?: "(pas de texte)"
            binding.proofSubmittedStatus.text = when (task.proof.status) {
                "pending" -> "En attente de validation"
                "accepted" -> "Preuve acceptée ✓"
                "rejected" -> "Preuve refusée"
                else -> task.proof.status
            }
            if (!task.proof.review_comment.isNullOrBlank()) {
                binding.proofSubmittedComment.visibility = View.VISIBLE
                binding.proofSubmittedComment.text = task.proof.review_comment
            } else {
                binding.proofSubmittedComment.visibility = View.GONE
            }
        } else {
            binding.proofFormSection.visibility = View.GONE
            binding.proofSubmittedSection.visibility = View.GONE
        }
    }

    private fun formatDate(iso: String): String {
        return try {
            val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
                timeZone = java.util.TimeZone.getTimeZone("UTC")
            }
            val date = parser.parse(iso.replace("Z", "").take(19))
            if (date != null) SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.getDefault()).format(date)
            else iso.take(16)
        } catch (_: Exception) {
            iso.take(16)
        }
    }

    private fun submitProof() {
        val text = binding.proofTextInput.text.toString().trim()
        val mediaFile = selectedMediaFile

        if (text.isEmpty() && mediaFile == null) {
            Toast.makeText(this, "Ajoute du texte ou une image/vidéo", Toast.LENGTH_SHORT).show()
            return
        }

        binding.proofSubmitButton.isEnabled = false

        lifecycleScope.launch {
            val result = repository.submitProof(deviceId, taskId, text.ifEmpty { null }, mediaFile)
            if (!isDestroyed) binding.proofSubmitButton.isEnabled = true
            if (isDestroyed) return@launch
            result.onSuccess {
                if (!isDestroyed) {
                    Toast.makeText(this@TaskDetailActivity, "Preuve envoyée", Toast.LENGTH_SHORT).show()
                    loadTaskDetail()
                }
            }.onFailure {
                if (!isDestroyed) Toast.makeText(this@TaskDetailActivity, "Erreur: ${it.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    override fun onSupportNavigateUp(): Boolean {
        finish()
        return true
    }
}

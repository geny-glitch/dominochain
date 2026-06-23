package com.bg

import android.content.Intent
import com.bg.api.RetrofitClient
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.bg.databinding.ActivityLoginBinding
import kotlinx.coroutines.launch

class LoginActivity : AppCompatActivity() {

    private lateinit var binding: ActivityLoginBinding
    private val sessionManager by lazy { (application as BgApplication).sessionManager }
    private val authRepository = AuthRepository()
    private var isRegisterMode = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityLoginBinding.inflate(layoutInflater)
        setContentView(binding.root)

        AppUpdateManager(this).checkForUpdates()

        RetrofitClient.sessionManager = sessionManager

        if (sessionManager.deviceId == null) {
            sessionManager.deviceId = java.util.UUID.randomUUID().toString()
        }

        if (sessionManager.isLoggedIn) {
            goToMain()
            return
        }

        binding.switchMode.setOnClickListener {
            isRegisterMode = !isRegisterMode
            updateFormVisibility()
        }

        binding.loginButton.setOnClickListener { doLogin() }
        binding.registerButton.setOnClickListener { doRegister() }

        updateFormVisibility()
    }

    private fun updateFormVisibility() {
        binding.loginForm.visibility = if (isRegisterMode) View.GONE else View.VISIBLE
        binding.registerForm.visibility = if (isRegisterMode) View.VISIBLE else View.GONE
        binding.switchMode.text = if (isRegisterMode) "J'ai déjà un compte" else "Créer un compte"
    }

    private fun doLogin() {
        val email = binding.loginEmail.text.toString().trim()
        val password = binding.loginPassword.text.toString()
        if (email.isBlank() || password.isBlank()) {
            Toast.makeText(this, "E-mail et mot de passe requis", Toast.LENGTH_SHORT).show()
            return
        }

        val deviceId = sessionManager.deviceId ?: run {
            val id = java.util.UUID.randomUUID().toString()
            sessionManager.deviceId = id
            id
        }

        binding.loginButton.isEnabled = false
        lifecycleScope.launch {
            val result = authRepository.login(
                email = email,
                password = password,
                deviceId = deviceId
            )
            binding.loginButton.isEnabled = true
            result.onSuccess { auth ->
                sessionManager.token = auth.token
                sessionManager.deviceId = auth.device_id ?: deviceId
                sessionManager.nickname = auth.user.nickname
                goToMain()
            }.onFailure {
                Toast.makeText(this@LoginActivity, it.message, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun doRegister() {
        val email = binding.registerEmail.text.toString().trim()
        val password = binding.registerPassword.text.toString()
        val passwordConfirm = binding.registerPasswordConfirm.text.toString()
        if (email.isBlank() || password.isBlank()) {
            Toast.makeText(this, "E-mail et mot de passe requis", Toast.LENGTH_SHORT).show()
            return
        }
        if (password.length < 6) {
            Toast.makeText(this, "Mot de passe : 6 caractères minimum", Toast.LENGTH_SHORT).show()
            return
        }
        if (password != passwordConfirm) {
            Toast.makeText(this, "Les mots de passe ne correspondent pas", Toast.LENGTH_SHORT).show()
            return
        }

        val deviceId = sessionManager.deviceId ?: run {
            val id = java.util.UUID.randomUUID().toString()
            sessionManager.deviceId = id
            id
        }

        binding.registerButton.isEnabled = false
        lifecycleScope.launch {
            val result = authRepository.register(
                email = email,
                password = password,
                passwordConfirmation = passwordConfirm,
                deviceId = deviceId
            )
            binding.registerButton.isEnabled = true
            result.onSuccess { auth ->
                sessionManager.token = auth.token
                sessionManager.deviceId = auth.device_id ?: deviceId
                sessionManager.nickname = auth.user.nickname
                goToMain()
            }.onFailure {
                Toast.makeText(this@LoginActivity, it.message, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun goToMain() {
        startActivity(Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        })
        finish()
    }
}

package app.dominochain.mobile

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Off-screen WebView bridge around the vendored tlock-js bundle.
 * Encryption happens on-device; original bytes are never sent before locking.
 */
class TlockBridge(private val context: Context) {
    data class EncryptResult(
        val armored: String,
        val round: Long,
        val chainHash: String?
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private var webView: WebView? = null
    private val readyLatch = CountDownLatch(1)
    private val resultRef = AtomicReference<String?>(null)
    private val errorRef = AtomicReference<String?>(null)
    private val callLatch = AtomicReference<CountDownLatch?>(null)

    @SuppressLint("SetJavaScriptEnabled")
    fun ensureReady(timeoutMs: Long = 20_000): Boolean {
        if (readyLatch.count == 0L) return true
        mainHandler.post {
            if (webView != null) return@post
            val view = WebView(context.applicationContext)
            view.settings.javaScriptEnabled = true
            view.settings.domStorageEnabled = true
            view.addJavascriptInterface(JsBridge(), "AndroidTlock")
            view.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    readyLatch.countDown()
                }
            }
            val base = BuildConfig.API_BASE_URL.trimEnd('/')
            val html = """
                <!DOCTYPE html>
                <html><head><meta charset="utf-8" /></head>
                <body>
                <script src="$base/vendor/tlock-js.js"></script>
                <script>
                  function utf8Bytes(str) { return new TextEncoder().encode(str); }
                  function bytesToUtf8(bytes) { return new TextDecoder().decode(bytes); }
                  function isArmoredAge(text) {
                    return typeof text === "string" && text.indexOf("-----BEGIN AGE ENCRYPTED FILE-----") !== -1;
                  }
                  function b64ToBytes(b64) {
                    const bin = atob(b64);
                    const out = new Uint8Array(bin.length);
                    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
                    return out;
                  }
                  function bytesToB64(bytes) {
                    let s = "";
                    const chunk = 0x8000;
                    for (let i = 0; i < bytes.length; i += chunk) {
                      s += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
                    }
                    return btoa(s);
                  }
                  async function encryptPayload(bytesOrString, lockedUntilMs) {
                    const api = window.TlockJs;
                    if (!api || typeof api.timelockEncrypt !== "function") {
                      throw new Error("Crypto library is not available");
                    }
                    const client = api.mainnetClient();
                    const chainInfo = api.defaultChainInfo || (await client.chain().info());
                    const round = api.roundAt(lockedUntilMs, chainInfo);
                    if (!Number.isFinite(round) || round < 1) throw new Error("Invalid drand round");
                    const payload = typeof bytesOrString === "string" ? utf8Bytes(bytesOrString) : bytesOrString;
                    const armored = await api.timelockEncrypt(round, api.Buffer.from(payload), client);
                    return { armored: armored, round: round, chainHash: chainInfo.hash };
                  }
                  window.__tlockEncryptBytes = async function(b64, lockedUntilMs) {
                    try {
                      const result = await encryptPayload(b64ToBytes(b64), lockedUntilMs);
                      AndroidTlock.onResult(JSON.stringify(result));
                    } catch (e) {
                      AndroidTlock.onError(String(e && e.message ? e.message : e));
                    }
                  };
                  window.__tlockEncryptOuter = async function(armoredB64, lockedUntilMs) {
                    try {
                      const armored = bytesToUtf8(b64ToBytes(armoredB64));
                      const result = await encryptPayload(armored, lockedUntilMs);
                      AndroidTlock.onResult(JSON.stringify(result));
                    } catch (e) {
                      AndroidTlock.onError(String(e && e.message ? e.message : e));
                    }
                  };
                  window.__tlockDecryptLayers = async function(outerArmoredB64, expectedLayers) {
                    try {
                      const api = window.TlockJs;
                      const client = api.mainnetClient();
                      let payload = bytesToUtf8(b64ToBytes(outerArmoredB64));
                      let layersPeeled = 0;
                      const max = expectedLayers || 20;
                      while (layersPeeled < max) {
                        const decrypted = await api.timelockDecrypt(payload, client);
                        layersPeeled += 1;
                        const asText = bytesToUtf8(decrypted);
                        if (isArmoredAge(asText)) { payload = asText; continue; }
                        AndroidTlock.onResult(JSON.stringify({
                          bytesBase64: bytesToB64(decrypted),
                          layersPeeled: layersPeeled
                        }));
                        return;
                      }
                      throw new Error("Too many tlock layers");
                    } catch (e) {
                      AndroidTlock.onError(String(e && e.message ? e.message : e));
                    }
                  };
                </script>
                </body></html>
            """.trimIndent()
            view.loadDataWithBaseURL(
                BuildConfig.API_BASE_URL,
                html,
                "text/html",
                "UTF-8",
                null
            )
            webView = view
        }
        return readyLatch.await(timeoutMs, TimeUnit.MILLISECONDS)
    }

    fun encryptBytes(bytes: ByteArray, lockedUntilMs: Long): EncryptResult {
        ensureReadyOrThrow()
        val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
        val json = callJs("window.__tlockEncryptBytes('$b64', $lockedUntilMs);")
        return parseEncrypt(json)
    }

    fun encryptOuter(armored: String, lockedUntilMs: Long): EncryptResult {
        ensureReadyOrThrow()
        val b64 = Base64.encodeToString(armored.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val json = callJs("window.__tlockEncryptOuter('$b64', $lockedUntilMs);")
        return parseEncrypt(json)
    }

    fun decryptLayers(armored: String, expectedLayers: Int): ByteArray {
        ensureReadyOrThrow()
        val b64 = Base64.encodeToString(armored.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val json = callJs("window.__tlockDecryptLayers('$b64', $expectedLayers);")
        val obj = JSONObject(json)
        return Base64.decode(obj.getString("bytesBase64"), Base64.DEFAULT)
    }

    fun destroy() {
        mainHandler.post {
            webView?.destroy()
            webView = null
        }
    }

    private fun ensureReadyOrThrow() {
        if (!ensureReady()) throw IllegalStateException("tlock bridge failed to load")
    }

    private fun callJs(script: String): String {
        val latch = CountDownLatch(1)
        callLatch.set(latch)
        resultRef.set(null)
        errorRef.set(null)
        mainHandler.post {
            webView?.evaluateJavascript(script, null)
        }
        if (!latch.await(60, TimeUnit.SECONDS)) {
            throw IllegalStateException("tlock operation timed out")
        }
        errorRef.get()?.let { throw IllegalStateException(it) }
        return resultRef.get() ?: throw IllegalStateException("Empty tlock result")
    }

    private fun parseEncrypt(json: String): EncryptResult {
        val obj = JSONObject(json)
        return EncryptResult(
            armored = obj.getString("armored"),
            round = obj.getLong("round"),
            chainHash = obj.optString("chainHash").ifBlank { null }
        )
    }

    private inner class JsBridge {
        @JavascriptInterface
        fun onResult(json: String) {
            resultRef.set(json)
            callLatch.get()?.countDown()
        }

        @JavascriptInterface
        fun onError(message: String) {
            errorRef.set(message)
            callLatch.get()?.countDown()
        }
    }
}

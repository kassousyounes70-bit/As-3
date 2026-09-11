import os
import math
from PIL import Image, ImageDraw

def create_adaptive_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    padding = int(size * 0.05)
    draw.rounded_rectangle([padding, padding, size - padding, size - padding], radius=int(size * 0.25), fill=(30, 136, 229, 255))
    
    cx, cy = size // 2, size // 2
    r = int(size * 0.2)
    
    draw.line([cx, cy - r, cx, cy + r], fill=(255, 255, 255, 255), width=max(2, int(size * 0.06)))
    draw.line([cx - r//1.2, cy + r//3, cx, cy + r], fill=(255, 255, 255, 255), width=max(2, int(size * 0.06)))
    draw.line([cx + r//1.2, cy + r//3, cx, cy + r], fill=(255, 255, 255, 255), width=max(2, int(size * 0.06)))
    draw.line([cx - r, cy + r + int(size * 0.08), cx + r, cy + r + int(size * 0.08)], fill=(255, 255, 255, 255), width=max(2, int(size * 0.06)))
    
    return img

def setup_project():
    print("Generating Android Project Scaffolding...")
    
    dirs = [
        "app/src/main/java/com/example/streamdownloader",
        "app/src/main/res/layout",
        "app/src/main/res/values",
        "app/src/main/res/mipmap-anydpi-v26",
        "gradle/wrapper"
    ]
    
    icon_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192
    }
    
    for d in dirs:
        os.makedirs(d, exist_ok=True)
        
    for mipmap, size in icon_sizes.items():
        os.makedirs(f"app/src/main/res/{mipmap}", exist_ok=True)
        icon = create_adaptive_icon(size)
        icon.save(f"app/src/main/res/{mipmap}/ic_launcher.png")
        icon.save(f"app/src/main/res/{mipmap}/ic_launcher_round.png")

    with open("settings.gradle.kts", "w", encoding="utf-8") as f:
        f.write('''pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "StreamDownloader"
include(":app")
''')

    with open("build.gradle.kts", "w", encoding="utf-8") as f:
        f.write('''plugins {
    id("com.android.application") version "8.2.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.22" apply false
}
''')

    with open("app/build.gradle.kts", "w", encoding="utf-8") as f:
        f.write('''plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.streamdownloader"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.example.streamdownloader"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
''')

    with open("app/src/main/AndroidManifest.xml", "w", encoding="utf-8") as f:
        f.write('''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="StreamDownloader"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:requestLegacyExternalStorage="true"
        android:theme="@style/Theme.Material3.DayNight.NoActionBar">
        
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
''')

    with open("gradle.properties", "w", encoding="utf-8") as f:
        f.write('''org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
''')

    with open("gradle/wrapper/gradle-wrapper.properties", "w", encoding="utf-8") as f:
        f.write('''distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-8.2-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
''')

    with open("app/src/main/java/com/example/streamdownloader/MainActivity.kt", "w", encoding="utf-8") as f:
        f.write('''package com.example.streamdownloader

import android.os.Bundle
import android.os.Environment
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.zip.ZipInputStream

class CountingInputStream(
    private val input: InputStream,
    private val onBytesRead: (Long) -> Unit
) : InputStream() {
    private var totalRead: Long = 0

    override fun read(): Int {
        val b = input.read()
        if (b != -1) {
            totalRead++
            onBytesRead(totalRead)
        }
        return b
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        val count = input.read(b, off, len)
        if (count > 0) {
            totalRead += count
            onBytesRead(totalRead)
        }
        return count
    }

    override fun close() {
        input.close()
    }
}

class MainActivity : AppCompatActivity() {

    private lateinit var statusTextView: TextView
    private lateinit var urlEditText: EditText
    private lateinit var startButton: Button
    private lateinit var progressBar: ProgressBar

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(50, 100, 50, 100)
        }

        urlEditText = EditText(this).apply {
            hint = "أدخل رابط ملف ZIP المباشر هنا"
            textSize = 14f
            setSingleLine(true)
        }
        
        startButton = Button(this).apply {
            text = "بدء التنزيل والفك المباشر"
            setOnClickListener {
                val url = urlEditText.text.toString().trim()
                if (url.isEmpty()) {
                    Toast.makeText(this@MainActivity, "الرجاء إدخال رابط صحيح", Toast.LENGTH_SHORT).show()
                } else {
                    startStreamingExtraction(url)
                }
            }
        }

        progressBar = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            progress = 0
            visibility = View.GONE
            setPadding(0, 30, 0, 30)
        }
        
        statusTextView = TextView(this).apply {
            text = "جاهز لبدء التنزيل والفك المباشر."
            textSize = 16f
            setPadding(0, 20, 0, 20)
        }
        
        layout.addView(urlEditText)
        layout.addView(startButton)
        layout.addView(progressBar)
        layout.addView(statusTextView)
        setContentView(layout)
    }

    private fun startStreamingExtraction(url: String) {
        lifecycleScope.launch(Dispatchers.IO) {
            updateUI("جاري الاتصال بالخادم...", 0, showProgress = true, isIndeterminate = true)
            try {
                val client = OkHttpClient()
                val request = Request.Builder().url(url).build()
                val response = client.newCall(request).execute()

                if (!response.isSuccessful || response.body == null) {
                    updateUI("فشل الاتصال: كود HTTP ${response.code}", 0, showProgress = false)
                    return@launch
                }

                val totalBytes = response.body!!.contentLength()
                val rawInputStream = response.body!!.byteStream()

                var lastUpdatedTime = 0L
                val countingStream = CountingInputStream(rawInputStream) { bytesRead ->
                    val currentTime = System.currentTimeMillis()
                    if (currentTime - lastUpdatedTime > 100 || bytesRead == totalBytes) {
                        lastUpdatedTime = currentTime
                        if (totalBytes > 0) {
                            val percent = ((bytesRead * 100) / totalBytes).toInt()
                            val downloadedMB = String.format("%.2f", bytesRead / (1024.0 * 1024.0))
                            val totalMB = String.format("%.2f", totalBytes / (1024.0 * 1024.0))
                            updateUI("جاري التنزيل والفك: $percent% ($downloadedMB MB / $totalMB MB)", percent, showProgress = true, isIndeterminate = false)
                        } else {
                            val downloadedMB = String.format("%.2f", bytesRead / (1024.0 * 1024.0))
                            updateUI("جاري التنزيل والفك: $downloadedMB MB", 0, showProgress = true, isIndeterminate = true)
                        }
                    }
                }

                val zipInputStream = ZipInputStream(countingStream)
                
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                val targetDir = File(downloadsDir, "StreamDownloader")
                if (!targetDir.exists()) targetDir.mkdirs()

                var entry = zipInputStream.nextEntry
                val buffer = ByteArray(8192)

                while (entry != null) {
                    if (!entry.isDirectory) {
                        val outputFile = File(targetDir, entry.name)
                        outputFile.parentFile?.mkdirs()
                        
                        FileOutputStream(outputFile).use { fos ->
                            var len: Int
                            while (zipInputStream.read(buffer).also { len = it } > 0) {
                                fos.write(buffer, 0, len)
                            }
                        }
                    }
                    zipInputStream.closeEntry()
                    entry = zipInputStream.nextEntry
                }

                zipInputStream.close()
                updateUI("تم استخراج الملف بنجاح! تجده في مجلد التحميلات (Downloads/StreamDownloader)", 100, showProgress = true, isIndeterminate = false)

            } catch (e: Exception) {
                updateUI("خطأ: ${e.localizedMessage}", 0, showProgress = false)
            }
        }
    }

    private suspend fun updateUI(msg: String, progressVal: Int, showProgress: Boolean, isIndeterminate: Boolean = false) {
        withContext(Dispatchers.Main) {
            statusTextView.text = msg
            progressBar.visibility = if (showProgress) View.VISIBLE else View.GONE
            progressBar.isIndeterminate = isIndeterminate
            if (!isIndeterminate) {
                progressBar.progress = progressVal
            }
        }
    }
}

package com.bg

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.bg.api.WallpaperItemResponse
import coil.load
import java.text.SimpleDateFormat
import java.util.Locale

class WallpapersAdapter : ListAdapter<WallpaperItemResponse, WallpapersAdapter.ViewHolder>(WallpaperDiffCallback()) {

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_wallpaper, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.bind(getItem(position))
    }

    inner class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val image: ImageView = view.findViewById(R.id.wallpaper_image)
        private val dateText: TextView = view.findViewById(R.id.wallpaper_date)

        fun bind(item: WallpaperItemResponse) {
            image.load(item.url)
            dateText.text = try {
                val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
                val date = parser.parse(item.created_at.replace("Z", "").take(19))
                if (date != null) {
                    SimpleDateFormat("dd/MM/yy", Locale.getDefault()).format(date)
                } else item.created_at.take(10)
            } catch (_: Exception) {
                item.created_at.take(10)
            }
        }
    }

    class WallpaperDiffCallback : DiffUtil.ItemCallback<WallpaperItemResponse>() {
        override fun areItemsTheSame(old: WallpaperItemResponse, new: WallpaperItemResponse) = old.id == new.id
        override fun areContentsTheSame(old: WallpaperItemResponse, new: WallpaperItemResponse) = old == new
    }
}

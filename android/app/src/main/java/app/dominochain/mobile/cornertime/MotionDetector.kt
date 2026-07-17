package app.dominochain.mobile.cornertime

interface MotionDetector {
    fun reset()
    fun onCalibrationFrame(luma: FloatArray, width: Int, height: Int)
    /** Returns motion score in 0..1 range, or null if not ready. */
    fun score(luma: FloatArray, width: Int, height: Int): Float?
}

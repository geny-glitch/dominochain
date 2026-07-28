import { Controller } from "@hotwired/stimulus"
import { PuzzleEngine } from "puzzle/engine"
import { postJson, postFormData } from "puzzle/api"

const BACKGROUND_STORAGE_KEY = "puzzle:board-background"
const DEFAULT_BACKGROUND = "#16161b"

export default class extends Controller {
  static targets = [
    "container",
    "progress",
    "timer",
    "reference",
    "referenceImage",
    "status",
    "startButton",
    "abandonButton",
    "playArea",
    "backgroundInput",
    "moveModeButton"
  ]

  static values = {
    sessionId: Number,
    referenceMode: String,
    deadlineAt: String,
    imageUrl: String,
    startUrl: String,
    finishUrl: String,
    snapshotUrl: String,
    piecesTotal: Number
  }

  connect() {
    this.engine = null
    this.timerInterval = null
    this.finishing = false
    this.i18n = this.readI18n()
    this.setupReference()
    this.setupBackground()
  }

  disconnect() {
    this.clearTimer()
    if (this.engine) this.engine.destroy()
  }

  readI18n() {
    const el = document.getElementById("puzzle-i18n")
    if (!el) return {}
    try {
      return JSON.parse(el.textContent)
    } catch (_e) {
      return {}
    }
  }

  setupReference() {
    if (!this.hasReferenceTarget) return
    const mode = this.referenceModeValue
    if (mode === "none") {
      this.referenceTarget.hidden = true
      return
    }
    this.referenceTarget.hidden = false
    if (this.hasReferenceImageTarget) {
      this.referenceImageTarget.src = this.imageUrlValue
      this.referenceImageTarget.classList.toggle("ds-puzzle-reference-img--blurred", mode === "blurred")
    }
  }

  // The board background is purely a display preference (not tied to the
  // session outcome), so it lives in localStorage rather than the backend.
  setupBackground() {
    if (!this.hasBackgroundInputTarget) return
    let stored = DEFAULT_BACKGROUND
    try {
      stored = window.localStorage.getItem(BACKGROUND_STORAGE_KEY) || DEFAULT_BACKGROUND
    } catch (_e) {
      // localStorage unavailable (private mode, etc.): fall back to the default.
    }
    this.backgroundInputTarget.value = stored
    this.applyBackground(stored)
  }

  changeBackground(event) {
    const color = event.target.value
    this.applyBackground(color)
    try {
      window.localStorage.setItem(BACKGROUND_STORAGE_KEY, color)
    } catch (_e) {
      // Ignore storage failures; the color still applies for this page view.
    }
  }

  applyBackground(color) {
    if (this.hasContainerTarget) this.containerTarget.style.setProperty("--ds-puzzle-bg", color)
  }

  // Off by default: dragging the board background is reserved for move mode
  // so it doesn't fight with picking up pieces near the edges of the board.
  toggleMoveMode(event) {
    event?.preventDefault()
    const enabled = !this.moveModeButtonTarget.classList.contains("is-active")
    this.moveModeButtonTarget.classList.toggle("is-active", enabled)
    this.moveModeButtonTarget.setAttribute("aria-pressed", String(enabled))
    if (this.engine) this.engine.setMoveMode(enabled)
  }

  zoomIn(event) {
    event?.preventDefault()
    this.engine?.zoomIn()
  }

  zoomOut(event) {
    event?.preventDefault()
    this.engine?.zoomOut()
  }

  async start(event) {
    event?.preventDefault()
    if (this.engine) return
    try {
      this.setStatus(this.i18n.starting || "Starting…")
      const started = await postJson(this.startUrlValue, {})
      if (started.deadline_at) this.deadlineAtValue = started.deadline_at
      // The container must be visible (and laid out) before the engine
      // measures it, otherwise it sizes every piece at 0x0.
      if (this.hasStartButtonTarget) this.startButtonTarget.hidden = true
      if (this.hasPlayAreaTarget) this.playAreaTarget.hidden = false
      this.engine = new PuzzleEngine({
        container: this.containerTarget,
        numPieces: this.piecesTotalValue,
        onProgress: (n, total) => this.updateProgress(n, total),
        onWin: () => this.complete()
      })
      await this.engine.loadImage(this.imageUrlValue)
      this.engine.start()
      this.updateProgress(0, this.engine.mergesTotal())
      this.startTimer()
      if (this.hasAbandonButtonTarget) this.abandonButtonTarget.hidden = false
      this.setStatus("")
    } catch (error) {
      this.setStatus(this.i18n.startFailed || "Could not start the puzzle.")
    }
  }

  updateProgress(n, total) {
    if (this.hasProgressTarget) {
      this.progressTarget.textContent = (this.i18n.progress || "{n}/{total}")
        .replace("{n}", String(n))
        .replace("{total}", String(total ?? this.piecesTotalValue))
    }
  }

  startTimer() {
    this.clearTimer()
    if (!this.deadlineAtValue || !this.hasTimerTarget) {
      if (this.hasTimerTarget) this.timerTarget.hidden = true
      return
    }
    this.timerTarget.hidden = false
    const tick = () => {
      const remaining = Math.max(0, Math.floor((Date.parse(this.deadlineAtValue) - Date.now()) / 1000))
      const mm = String(Math.floor(remaining / 60)).padStart(2, "0")
      const ss = String(remaining % 60).padStart(2, "0")
      this.timerTarget.textContent = `${mm}:${ss}`
      if (remaining <= 0) this.timeout()
    }
    tick()
    this.timerInterval = window.setInterval(tick, 1000)
  }

  clearTimer() {
    if (this.timerInterval) {
      window.clearInterval(this.timerInterval)
      this.timerInterval = null
    }
  }

  async complete() {
    if (this.finishing) return
    this.finishing = true
    this.clearTimer()
    this.setStatus(this.i18n.finishing || "Finishing…")
    try {
      await postJson(this.finishUrlValue, {
        outcome: "complete",
        pieces_placed: this.piecesTotalValue
      })
      this.setStatus(this.i18n.completed || "Puzzle complete.")
      if (this.hasAbandonButtonTarget) this.abandonButtonTarget.hidden = true
    } catch (_e) {
      this.finishing = false
      this.setStatus(this.i18n.finishFailed || "Could not save the result.")
    }
  }

  async abandon(event) {
    event?.preventDefault()
    if (this.finishing) return
    if (!window.confirm(this.i18n.abandonConfirm || "Give up on this puzzle?")) return
    await this.endWithOutcome("abandon")
  }

  async timeout() {
    if (this.finishing) return
    await this.endWithOutcome("timeout")
  }

  async endWithOutcome(outcome) {
    this.finishing = true
    this.clearTimer()
    this.setStatus(this.i18n.finishing || "Finishing…")
    try {
      if (this.engine) {
        const piecesPlaced = this.engine.mergesDone()
        const blob = await this.engine.exportProgressBlob()
        if (blob) {
          const form = new FormData()
          form.append("snapshot", blob, "progress.png")
          form.append("pieces_placed", String(piecesPlaced))
          await postFormData(this.snapshotUrlValue, form)
        }
        await postJson(this.finishUrlValue, { outcome, pieces_placed: piecesPlaced })
      } else {
        await postJson(this.finishUrlValue, { outcome })
      }
      this.setStatus(
        outcome === "timeout"
          ? (this.i18n.timedOut || "Time is up.")
          : (this.i18n.abandoned || "Puzzle abandoned.")
      )
      if (this.hasAbandonButtonTarget) this.abandonButtonTarget.hidden = true
    } catch (_e) {
      this.finishing = false
      this.setStatus(this.i18n.finishFailed || "Could not save the result.")
    }
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text || ""
  }
}

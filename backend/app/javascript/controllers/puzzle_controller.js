import { Controller } from "@hotwired/stimulus"
import { PuzzleEngine } from "puzzle/engine"
import { postJson, postFormData } from "puzzle/api"

export default class extends Controller {
  static targets = [
    "canvas",
    "progress",
    "timer",
    "reference",
    "referenceImage",
    "status",
    "startButton",
    "abandonButton",
    "playArea"
  ]

  static values = {
    sessionId: Number,
    layoutSeed: Number,
    gridCols: Number,
    gridRows: Number,
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
  }

  disconnect() {
    this.clearTimer()
    if (this.engine) this.engine.detach()
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

  async start(event) {
    event?.preventDefault()
    if (this.engine) return
    try {
      this.setStatus(this.i18n.starting || "Starting…")
      const started = await postJson(this.startUrlValue, {})
      if (started.deadline_at) this.deadlineAtValue = started.deadline_at
      this.engine = new PuzzleEngine({
        canvas: this.canvasTarget,
        cols: this.gridColsValue,
        rows: this.gridRowsValue,
        layoutSeed: this.layoutSeedValue,
        onProgress: (n) => this.updateProgress(n),
        onComplete: (positions) => this.complete(positions)
      })
      await this.engine.loadImage(this.imageUrlValue)
      this.engine.attach()
      this.updateProgress(0)
      this.startTimer()
      if (this.hasStartButtonTarget) this.startButtonTarget.hidden = true
      if (this.hasAbandonButtonTarget) this.abandonButtonTarget.hidden = false
      if (this.hasPlayAreaTarget) this.playAreaTarget.hidden = false
      this.setStatus("")
    } catch (error) {
      this.setStatus(this.i18n.startFailed || "Could not start the puzzle.")
    }
  }

  updateProgress(n) {
    if (this.hasProgressTarget) {
      const total = this.piecesTotalValue
      this.progressTarget.textContent = (this.i18n.progress || "{n}/{total}")
        .replace("{n}", String(n))
        .replace("{total}", String(total))
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

  async complete(positions) {
    if (this.finishing) return
    this.finishing = true
    this.clearTimer()
    this.setStatus(this.i18n.finishing || "Finishing…")
    try {
      await postJson(this.finishUrlValue, {
        outcome: "complete",
        pieces_placed: this.piecesTotalValue,
        piece_positions: positions
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
        const blob = await this.engine.exportProgressBlob()
        if (blob) {
          const form = new FormData()
          form.append("snapshot", blob, "progress.png")
          form.append("pieces_placed", String(this.engine.piecesPlaced()))
          await postFormData(this.snapshotUrlValue, form)
        }
        await postJson(this.finishUrlValue, {
          outcome,
          pieces_placed: this.engine.piecesPlaced(),
          piece_positions: this.engine.piecePositions()
        })
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

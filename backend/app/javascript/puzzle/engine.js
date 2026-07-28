import { JigsawPuzzle } from "jigsawpuzzlegame"

// jigsawpuzzlegame supports shape types 0-3; 3 gives the roundest, most
// classic-looking knobs.
const DEFAULT_SHAPE_TYPE = 0

// Thin wrapper around the jigsawpuzzlegame library: pieces interlock freely
// (no fixed board grid) and merge into groups until only one remains.
export class PuzzleEngine {
  constructor({ container, numPieces, allowRotation = false, shapeType = DEFAULT_SHAPE_TYPE, onReady, onStart, onWin, onProgress }) {
    this.container = container
    this.numPieces = numPieces
    this.allowRotation = allowRotation
    this.shapeType = shapeType
    this.onReadyCallback = onReady || (() => {})
    this.onStartCallback = onStart || (() => {})
    this.onWinCallback = onWin || (() => {})
    this.onProgressCallback = onProgress || (() => {})
    this.groupsRemaining = numPieces
    // The library may round numPieces slightly to keep piece cells near 1:1
    // (e.g. asking for 20 on a portrait photo can yield 4x5 = 20, or nearby),
    // so the real piece count is only known once the internal grid exists.
    // Synced in start() and used in mergesTotal().
    this.actualPieceCount = null
    this.puzzle = null
    // Dragging empty background pans the whole board by default in the
    // library; we only want that once the user opts into "move mode" (see
    // setMoveMode / vetoBackgroundDrag).
    this.moveModeEnabled = false
    this.vetoBackgroundDrag = this.vetoBackgroundDrag.bind(this)
    this.vetoZoomGesture = this.vetoZoomGesture.bind(this)
  }

  loadImage(url) {
    return new Promise((resolve) => {
      // Registered before the JigsawPuzzle instance below adds its own
      // mousedown/touchstart/wheel listeners on the same container element,
      // so ours run first (DOM dispatch order for same-target listeners
      // follows registration order) and can veto the gesture before theok
      // library ever sees it.
      this.container.addEventListener("mousedown", this.vetoBackgroundDrag)
      this.container.addEventListener("touchstart", this.vetoBackgroundDrag)
      // Zoom is now driven exclusively by the +/- buttons; block the
      // library's own scroll-wheel and two-finger pinch zoom gestures.
      this.container.addEventListener("wheel", this.vetoZoomGesture, { passive: false })
      this.container.addEventListener("touchstart", this.vetoZoomGesture)

      this.puzzle = new JigsawPuzzle(this.container, {
        image: url,
        numPieces: this.numPieces,
        shapeType: this.shapeType,
        allowRotation: this.allowRotation,
        // We never pass savedData, so every session starts a brand new game:
        // this tells the library to scatter pieces across the board instead
        // of leaving them stacked in a pile (its default for a fresh game).
        initialFullySpreadPieces: true,
        onReady: () => {
          resolve()
          this.onReadyCallback()
        },
        onStart: () => this.onStartCallback(),
        // The library's actual piece grid can differ slightly from the
        // requested numPieces (it rounds to fit the image's aspect ratio),
        // so our merge-based counter can land one short of its own total
        // when the puzzle is actually solved. Force it to read as fully
        // complete here rather than trusting the last onMerged tally.
        onWin: () => {
          this.groupsRemaining = 1
          this.onProgressCallback(this.mergesTotal(), this.mergesTotal())
          this.onWinCallback()
        },
        onMerged: () => {
          this.groupsRemaining = Math.max(1, this.groupsRemaining - 1)
          this.onProgressCallback(this.mergesDone(), this.mergesTotal())
        }
      })
    })
  }

  start() {
    this.puzzle?.start()
    this.syncActualPieceCount()
  }

  // Clicking directly on a piece must always work (that's how you play);
  // only a drag that starts on truly empty board space is affected by move
  // mode. We replicate the library's own hit test so this stays correct
  // even where a piece's transparent canvas padding overlaps empty space.
  vetoBackgroundDrag(event) {
    if (this.moveModeEnabled) return
    const internal = this.puzzle?.puzzle
    if (!internal?.polyPieces) return
    const point = internal.relativeMouseCoordinates(event.touches ? event.touches[0] : event)
    const onPiece = internal.polyPieces.some((piece) => piece.isPointInPath(point))
    if (onPiece) return
    event.preventDefault()
    event.stopImmediatePropagation()
  }

  setMoveMode(enabled) {
    this.moveModeEnabled = enabled
  }

  // Wheel always means "zoom" to the library, and a second touch landing
  // anywhere starts a pinch; both are vetoed unconditionally since the +/-
  // buttons are now the only intended way to zoom.
  vetoZoomGesture(event) {
    if (event.type !== "wheel" && (!event.touches || event.touches.length < 2)) return
    event.preventDefault()
    event.stopImmediatePropagation()
  }

  zoomIn() {
    this.zoomBy(1.3)
  }

  zoomOut() {
    this.zoomBy(1 / 1.3)
  }

  zoomBy(factor) {
    const internal = this.puzzle?.puzzle
    if (!internal) return
    internal.zoomBy(factor, { x: internal.contWidth / 2, y: internal.contHeight / 2 })
  }

  // Piece creation happens asynchronously inside the library's own animation
  // loop, so poll a couple of frames until the real grid exists, then correct
  // our counters (and the UI) to match it instead of the requested numPieces.
  syncActualPieceCount() {
    if (!this.puzzle) return
    const count = this.puzzle.puzzle?.polyPieces?.length
    if (count) {
      this.actualPieceCount = count
      this.groupsRemaining = count
      this.onProgressCallback(this.mergesDone(), this.mergesTotal())
    } else if (!this.actualPieceCount) {
      requestAnimationFrame(() => this.syncActualPieceCount())
    }
  }

  // Every merge reduces the number of independent piece groups by one;
  // the puzzle is solved once a single group remains, so this is the
  // natural unit of progress for a free-form (non-grid) jigsaw.
  mergesTotal() {
    return Math.max(1, (this.actualPieceCount || this.numPieces) - 1)
  }

  mergesDone() {
    return this.mergesTotal() - (this.groupsRemaining - 1)
  }

  isComplete() {
    return this.groupsRemaining <= 1
  }

  async exportProgressBlob() {
    const canvas = this.composeProgressImage()
    if (!canvas) return null
    return new Promise((resolve) => canvas.toBlob((blob) => resolve(blob), "image/png"))
  }

  // Progress snapshot for sanctions: full original, heavily blurred, with every
  // assembled group (2+ pieces) drawn sharp on top. Lone pieces are discarded.
  composeProgressImage() {
    const internal = this.puzzle?.puzzle
    const src = internal?.srcImage
    if (!internal || !src?.naturalWidth || !Array.isArray(internal.polyPieces) || !internal.polyPieces.length) {
      return null
    }

    const width = Math.max(1, Math.round(src.naturalWidth))
    const height = Math.max(1, Math.round(src.naturalHeight))
    const canvas = document.createElement("canvas")
    canvas.width = width
    canvas.height = height
    const ctx = canvas.getContext("2d")
    if (!ctx) return null

    this.drawBlurredOriginal(ctx, src, width, height)

    const assembled = internal.polyPieces.filter((piece) => (piece.pieces?.length || 0) >= 2)
    assembled.forEach((piece) => {
      if (piece.canvas) this.drawPolyPieceOnImage(ctx, internal, piece, width, height)
    })
    return canvas
  }

  drawBlurredOriginal(ctx, src, width, height) {
    const blurPx = Math.max(16, Math.round(Math.min(width, height) * 0.045))
    const pad = blurPx * 2
    const scale = (Math.max(width, height) + pad * 2) / Math.max(width, height)
    const drawW = width * scale
    const drawH = height * scale
    ctx.save()
    ctx.filter = `blur(${blurPx}px)`
    // Oversized, aspect-preserving draw so blur does not leave sharp edges.
    ctx.drawImage(src, (width - drawW) / 2, (height - drawH) / 2, drawW, drawH)
    ctx.restore()
  }

  // PolyPiece canvases are unrotated bitmaps of the assembled chunk; map the
  // group's grid bounds onto the full source image and draw it sharp on top.
  drawPolyPieceOnImage(ctx, internal, polyPiece, width, height) {
    const gameWidth = internal.gameWidth || internal.scalex * internal.nx
    const gameHeight = internal.gameHeight || internal.scaley * internal.ny
    if (!(gameWidth > 0) || !(gameHeight > 0)) return

    const scaleX = width / gameWidth
    const scaleY = height / gameHeight
    const destX = (polyPiece.pckxmin - 0.5) * internal.scalex * scaleX
    const destY = (polyPiece.pckymin - 0.5) * internal.scaley * scaleY
    const destW = polyPiece.canvas.width * scaleX
    const destH = polyPiece.canvas.height * scaleY

    ctx.drawImage(polyPiece.canvas, destX, destY, destW, destH)
  }

  destroy() {
    this.container.removeEventListener("mousedown", this.vetoBackgroundDrag)
    this.container.removeEventListener("touchstart", this.vetoBackgroundDrag)
    this.container.removeEventListener("wheel", this.vetoZoomGesture)
    this.container.removeEventListener("touchstart", this.vetoZoomGesture)
    this.puzzle?.destroy()
    this.puzzle = null
  }
}

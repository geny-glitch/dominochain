// Deterministic mulberry32 PRNG from a numeric seed.
function mulberry32(seed) {
  let t = seed >>> 0
  return function () {
    t += 0x6d2b79f5
    let r = Math.imul(t ^ (t >>> 15), 1 | t)
    r ^= r + Math.imul(r ^ (r >>> 7), 61 | r)
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296
  }
}

function shuffle(array, random) {
  const out = array.slice()
  for (let i = out.length - 1; i > 0; i -= 1) {
    const j = Math.floor(random() * (i + 1))
    const tmp = out[i]
    out[i] = out[j]
    out[j] = tmp
  }
  return out
}

export class PuzzleEngine {
  constructor({ canvas, cols, rows, layoutSeed, onProgress, onComplete }) {
    this.canvas = canvas
    this.ctx = canvas.getContext("2d")
    this.cols = cols
    this.rows = rows
    this.pieceCount = cols * rows
    this.layoutSeed = layoutSeed
    this.onProgress = onProgress || (() => {})
    this.onComplete = onComplete || (() => {})
    this.image = null
    this.board = Array(this.pieceCount).fill(null)
    this.tray = []
    this.dragging = null
    this.boardRect = { x: 0, y: 0, w: 0, h: 0 }
    this.trayRect = { x: 0, y: 0, w: 0, h: 0 }
    this.pieceW = 0
    this.pieceH = 0
    this.raf = null
    this._boundPointerDown = this.onPointerDown.bind(this)
    this._boundPointerMove = this.onPointerMove.bind(this)
    this._boundPointerUp = this.onPointerUp.bind(this)
  }

  async loadImage(url) {
    const img = new Image()
    img.crossOrigin = "anonymous"
    await new Promise((resolve, reject) => {
      img.onload = resolve
      img.onerror = reject
      img.src = url
    })
    this.image = img
    this.resetPieces()
    this.layout()
    this.draw()
  }

  resetPieces() {
    const random = mulberry32(this.layoutSeed)
    const indices = Array.from({ length: this.pieceCount }, (_, i) => i)
    this.tray = shuffle(indices, random).map((pieceIndex, order) => ({
      pieceIndex,
      trayOrder: order,
      placed: false
    }))
    this.board = Array(this.pieceCount).fill(null)
  }

  layout() {
    const dpr = window.devicePixelRatio || 1
    const cssW = this.canvas.clientWidth || 360
    const cssH = Math.max(420, Math.round(cssW * 1.35))
    this.canvas.width = Math.round(cssW * dpr)
    this.canvas.height = Math.round(cssH * dpr)
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)

    const pad = 12
    const boardSize = Math.min(cssW - pad * 2, Math.round(cssH * 0.58))
    this.boardRect = {
      x: (cssW - boardSize) / 2,
      y: pad,
      w: boardSize,
      h: boardSize
    }
    this.pieceW = this.boardRect.w / this.cols
    this.pieceH = this.boardRect.h / this.rows
    this.trayRect = {
      x: pad,
      y: this.boardRect.y + this.boardRect.h + 16,
      w: cssW - pad * 2,
      h: cssH - (this.boardRect.y + this.boardRect.h + 28)
    }
  }

  attach() {
    this.canvas.addEventListener("pointerdown", this._boundPointerDown)
    window.addEventListener("pointermove", this._boundPointerMove)
    window.addEventListener("pointerup", this._boundPointerUp)
    window.addEventListener("pointercancel", this._boundPointerUp)
  }

  detach() {
    this.canvas.removeEventListener("pointerdown", this._boundPointerDown)
    window.removeEventListener("pointermove", this._boundPointerMove)
    window.removeEventListener("pointerup", this._boundPointerUp)
    window.removeEventListener("pointercancel", this._boundPointerUp)
  }

  piecesPlaced() {
    return this.board.filter((v) => v !== null).length
  }

  piecePositions() {
    // Returns cell occupancy: index = pieceIndex, value = cellIndex (or -1 if unplaced).
    const positions = Array(this.pieceCount).fill(-1)
    this.board.forEach((pieceIndex, cellIndex) => {
      if (pieceIndex !== null) positions[pieceIndex] = cellIndex
    })
    return positions
  }

  isComplete() {
    return this.board.every((pieceIndex, cellIndex) => pieceIndex === cellIndex)
  }

  onPointerDown(event) {
    if (!this.image) return
    const point = this.eventPoint(event)
    const trayHit = this.hitTray(point)
    if (trayHit) {
      this.dragging = {
        pieceIndex: trayHit.pieceIndex,
        from: "tray",
        offsetX: point.x - trayHit.x,
        offsetY: point.y - trayHit.y,
        x: trayHit.x,
        y: trayHit.y
      }
      this.tray = this.tray.filter((p) => p.pieceIndex !== trayHit.pieceIndex)
      this.canvas.setPointerCapture(event.pointerId)
      this.draw()
      return
    }

    const boardHit = this.hitBoard(point)
    if (boardHit && this.board[boardHit.cellIndex] !== null) {
      const pieceIndex = this.board[boardHit.cellIndex]
      this.board[boardHit.cellIndex] = null
      this.dragging = {
        pieceIndex,
        from: "board",
        fromCell: boardHit.cellIndex,
        offsetX: point.x - boardHit.x,
        offsetY: point.y - boardHit.y,
        x: boardHit.x,
        y: boardHit.y
      }
      this.onProgress(this.piecesPlaced())
      this.canvas.setPointerCapture(event.pointerId)
      this.draw()
    }
  }

  onPointerMove(event) {
    if (!this.dragging) return
    const point = this.eventPoint(event)
    this.dragging.x = point.x - this.dragging.offsetX
    this.dragging.y = point.y - this.dragging.offsetY
    this.draw()
  }

  onPointerUp() {
    if (!this.dragging) return
    const { pieceIndex, x, y } = this.dragging
    const cell = this.cellAt(x + this.pieceW / 2, y + this.pieceH / 2)
    if (cell !== null && this.board[cell] === null) {
      this.board[cell] = pieceIndex
      this.onProgress(this.piecesPlaced())
      if (this.isComplete()) this.onComplete(this.piecePositions())
    } else {
      this.tray.push({ pieceIndex, trayOrder: this.tray.length, placed: false })
    }
    this.dragging = null
    this.draw()
  }

  eventPoint(event) {
    const rect = this.canvas.getBoundingClientRect()
    return {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top
    }
  }

  cellAt(x, y) {
    const { boardRect, cols, rows, pieceW, pieceH } = this
    if (x < boardRect.x || y < boardRect.y || x > boardRect.x + boardRect.w || y > boardRect.y + boardRect.h) {
      return null
    }
    const col = Math.min(cols - 1, Math.max(0, Math.floor((x - boardRect.x) / pieceW)))
    const row = Math.min(rows - 1, Math.max(0, Math.floor((y - boardRect.y) / pieceH)))
    return row * cols + col
  }

  hitBoard(point) {
    const cell = this.cellAt(point.x, point.y)
    if (cell === null) return null
    const col = cell % this.cols
    const row = Math.floor(cell / this.cols)
    return {
      cellIndex: cell,
      x: this.boardRect.x + col * this.pieceW,
      y: this.boardRect.y + row * this.pieceH
    }
  }

  hitTray(point) {
    const unplaced = this.tray
    if (!unplaced.length) return null
    const gap = 8
    const size = Math.min(this.pieceW * 0.85, this.pieceH * 0.85, 72)
    const perRow = Math.max(1, Math.floor((this.trayRect.w + gap) / (size + gap)))
    for (let i = 0; i < unplaced.length; i += 1) {
      const col = i % perRow
      const row = Math.floor(i / perRow)
      const x = this.trayRect.x + col * (size + gap)
      const y = this.trayRect.y + row * (size + gap)
      if (point.x >= x && point.x <= x + size && point.y >= y && point.y <= y + size) {
        return { pieceIndex: unplaced[i].pieceIndex, x, y, size }
      }
    }
    return null
  }

  drawPiece(pieceIndex, dx, dy, dw, dh) {
    if (!this.image) return
    const col = pieceIndex % this.cols
    const row = Math.floor(pieceIndex / this.cols)
    const sw = this.image.naturalWidth / this.cols
    const sh = this.image.naturalHeight / this.rows
    this.ctx.save()
    this.ctx.drawImage(this.image, col * sw, row * sh, sw, sh, dx, dy, dw, dh)
    this.ctx.strokeStyle = "rgba(255,255,255,0.35)"
    this.ctx.lineWidth = 1
    this.ctx.strokeRect(dx + 0.5, dy + 0.5, dw - 1, dh - 1)
    this.ctx.restore()
  }

  draw() {
    const { ctx, canvas, boardRect, trayRect } = this
    const cssW = canvas.clientWidth || 360
    const cssH = canvas.height / (window.devicePixelRatio || 1)
    ctx.clearRect(0, 0, cssW, cssH)

    ctx.fillStyle = "rgba(255,255,255,0.06)"
    ctx.fillRect(boardRect.x, boardRect.y, boardRect.w, boardRect.h)
    ctx.strokeStyle = "rgba(255,255,255,0.2)"
    ctx.strokeRect(boardRect.x, boardRect.y, boardRect.w, boardRect.h)

    for (let cell = 0; cell < this.pieceCount; cell += 1) {
      const col = cell % this.cols
      const row = Math.floor(cell / this.cols)
      const x = boardRect.x + col * this.pieceW
      const y = boardRect.y + row * this.pieceH
      ctx.strokeStyle = "rgba(255,255,255,0.08)"
      ctx.strokeRect(x, y, this.pieceW, this.pieceH)
      const pieceIndex = this.board[cell]
      if (pieceIndex !== null) this.drawPiece(pieceIndex, x, y, this.pieceW, this.pieceH)
    }

    const gap = 8
    const size = Math.min(this.pieceW * 0.85, this.pieceH * 0.85, 72)
    const perRow = Math.max(1, Math.floor((trayRect.w + gap) / (size + gap)))
    this.tray.forEach((item, i) => {
      const col = i % perRow
      const row = Math.floor(i / perRow)
      const x = trayRect.x + col * (size + gap)
      const y = trayRect.y + row * (size + gap)
      this.drawPiece(item.pieceIndex, x, y, size, size)
    })

    if (this.dragging) {
      this.drawPiece(this.dragging.pieceIndex, this.dragging.x, this.dragging.y, this.pieceW, this.pieceH)
    }
  }

  exportProgressBlob() {
    return new Promise((resolve) => {
      this.canvas.toBlob((blob) => resolve(blob), "image/png")
    })
  }
}

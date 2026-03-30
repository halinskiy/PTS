# PTS Web Component — Full Specification

Create a React+TypeScript component that renders the PTS pixel-art pet walking along the bottom of a webpage. The pet must look **pixel-identical** to the native macOS version.

## Target Site
- Vite + React + TypeScript
- Site repo: `/Users/3mpq/3mpq-studio-export/`
- The component goes at the bottom of the page, above or inside the footer dock area
- Use `<canvas>` for rendering (HTML Canvas2D API)

---

## 1. PIXEL DATA (exact copy from native app)

### Body Grid (10 columns × 7 rows)
Values: 0 = empty, 1 = body, 2 = screen (rendered same color as body)

```typescript
const BODY_GRID = [
  [0, 1, 1, 1, 1, 1, 1, 1, 1, 0], // row 0 — top
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], // row 1
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], // row 2 (screen area, same color)
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], // row 3 (eyes go here)
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], // row 4
  [1, 1, 1, 1, 1, 1, 1, 1, 1, 1], // row 5
  [0, 1, 1, 1, 1, 1, 1, 1, 1, 0], // row 6 — bottom edge
];
```

Note: In the native app, values 1 and 2 are both rendered with the same `bodyColor` (uniform tint). So treat all non-zero values as body color.

### Leg Configurations (10 columns × 2 rows each)

```typescript
const LEGS_IDLE = [
  [0, 1, 0, 0, 0, 0, 0, 0, 1, 0],
  [0, 1, 0, 0, 0, 0, 0, 0, 1, 0],
];

const LEGS_WALK = [
  [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
  [1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
];
```

### Colors

```typescript
const BODY_COLOR = "#E87830";  // orange (default tint)
const EYE_COLOR  = "#000000";  // pure black
```

### Scale & Dimensions

```typescript
const SCALE = 3;  // each pixel = 3×3 CSS pixels

// Derived dimensions:
// Body: 10 cols × 7 rows = 30px × 21px (at scale 3)
// Legs: 10 cols × 2 rows = 30px × 6px
// Total sprite: 30px wide × 27px tall
// Eye positions: row 3 (from top), columns 3 and 6
```

---

## 2. RENDERING (Canvas2D)

### Coordinate System
The native app uses Cocoa coordinates (Y=0 at bottom). For web canvas, Y=0 is at top. **Flip the row order**: body row 0 (top of character) draws at y=0 in canvas.

### Draw Function

```typescript
function drawPet(
  ctx: CanvasRenderingContext2D,
  x: number,           // pet center X on canvas
  y: number,           // pet bottom Y (feet position)
  facingRight: boolean,
  legs: number[][],     // LEGS_IDLE or LEGS_WALK
  lookDir: number,      // -1, 0, or 1 (eye shift direction)
  bodyBob: number,      // 0-1 breathing offset in pixels
) {
  const s = SCALE;
  const bodyW = 10 * s;
  const bodyH = BODY_GRID.length * s;
  const legH = legs.length * s;

  // Origin: top-left of the sprite
  const ox = x - bodyW / 2;
  const oy = y - bodyH - legH + bodyBob;

  ctx.imageSmoothingEnabled = false;

  // Helper: maps grid column to canvas X, respecting facingRight
  const px = (col: number): number => {
    if (facingRight) return ox + col * s;
    return ox + (9 - col) * s;  // mirror
  };

  // Draw legs
  ctx.fillStyle = BODY_COLOR;
  for (let row = 0; row < legs.length; row++) {
    for (let col = 0; col < legs[row].length; col++) {
      if (legs[row][col] === 1) {
        ctx.fillRect(px(col), oy + bodyH + row * s, s, s);
      }
    }
  }

  // Draw body
  for (let row = 0; row < BODY_GRID.length; row++) {
    for (let col = 0; col < BODY_GRID[row].length; col++) {
      if (BODY_GRID[row][col] !== 0) {
        ctx.fillRect(px(col), oy + row * s, s, s);
      }
    }
  }

  // Draw eyes (row 3, columns 3 and 6)
  ctx.fillStyle = EYE_COLOR;
  const eyeRow = 3;
  const eyeShift = lookDir * (s - 2);  // shift by up to (scale - 2) pixels
  const leftEyeCol = 3;
  const rightEyeCol = 6;
  ctx.fillRect(px(leftEyeCol) + eyeShift, oy + eyeRow * s, s, s);
  ctx.fillRect(px(rightEyeCol) + eyeShift, oy + eyeRow * s, s, s);
}
```

### Key Rendering Rules
- `ctx.imageSmoothingEnabled = false` — crisp pixel art, no blurring
- All shapes are axis-aligned rectangles (`fillRect`) — no paths, no curves
- When `facingRight = false`, mirror X: column 0 draws at the right side
- Eye shift: `lookDir` is -1 (look left), 0 (center), or 1 (look right). Shift = `lookDir * (SCALE - 2)` pixels

---

## 3. ANIMATION STATE MACHINE

### States

```typescript
type PetState = "walking" | "idle" | "following" | "exited";
```

### Walk Animation
- Alternate between `LEGS_IDLE` and `LEGS_WALK` every **150ms**
- Move X by **1.5px per frame** (at 60fps = 90px/sec)
- `facingRight` = true when walking right, false when walking left
- Breathing: `bodyBob = Math.max(0, Math.sin(time * Math.PI * 2 / 1.2)) * SCALE * 0.2`

### Idle Animation
- Legs = `LEGS_IDLE`
- Breathing continues
- Eyes can shift toward cursor if nearby

### Follow Cursor Animation
- Same as walking but target = cursor X position
- When within 5px of cursor: stop, idle, look at cursor
- Walk speed slightly faster: **2px per frame**

---

## 4. SCENARIO TIMELINE (loop)

```
0s      — Pet appears at left edge (x = -30), walks right
3-5s    — Fake cursor appears (fade in, 0.5s) at ~60% of container width
         Pet stops walking, enters "idle", looks at cursor
5-6s    — Cursor starts moving slowly right
         Pet enters "following" state, walks toward cursor
6-9s    — Cursor moves right across ~30% of screen, pet follows
9-10s   — Cursor fades out (opacity 0.5s ease)
         Pet resumes "walking" right (facingRight = true)
~12-15s — Pet walks off right edge (x > containerWidth + 30)
         Pet enters "exited" state
+30s    — After 30 second pause, reset: pet appears at left edge
         New cycle begins
```

### Fake Cursor
- Render as a CSS `div` (or canvas draw) with a standard macOS arrow cursor image
- Or use a simple SVG arrow: white fill, black outline, ~16×20px
- Position: absolute, follows a scripted path (not real mouse)
- Fade in: `opacity 0 → 1` over 0.5s
- Fade out: `opacity 1 → 0` over 0.5s
- Movement: smooth easing (`ease-in-out`), moves ~200-400px rightward over 3-4s

---

## 5. REACT COMPONENT STRUCTURE

```typescript
// PtsDockPet.tsx
export function PtsDockPet() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [state, setState] = useState<PetState>("walking");

  useEffect(() => {
    // Animation loop with requestAnimationFrame
    // State machine logic
    // Canvas rendering
  }, []);

  return (
    <div style={{ position: "relative", width: "100%", height: 40, overflow: "hidden" }}>
      <canvas ref={canvasRef} style={{ imageRendering: "pixelated" }} />
      {/* Fake cursor overlay */}
      <div className="fake-cursor" style={{ ... }} />
    </div>
  );
}
```

### Container
- Full width of parent
- Height: ~40-50px (enough for pet sprite + padding)
- `overflow: hidden` — pet disappears at edges
- Position at the bottom of the page, in/near the footer dock

### Canvas
- Width = container width, height = container height
- Style: `imageRendering: "pixelated"` (or `-webkit-optimize-contrast` for Safari)
- DPR-aware: multiply canvas dimensions by `window.devicePixelRatio`

---

## 6. CSS FOR FAKE CURSOR

```css
.fake-cursor {
  position: absolute;
  width: 16px;
  height: 20px;
  pointer-events: none;
  transition: opacity 0.5s ease;
  /* Use a cursor SVG or emoji */
  background-image: url("data:image/svg+xml,..."); /* macOS-style arrow */
  background-size: contain;
  z-index: 10;
}
```

### macOS Arrow Cursor SVG (inline)
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="20" viewBox="0 0 16 20">
  <path d="M0 0 L0 16 L4 12 L7 19 L9 18 L6 11 L12 11 Z" fill="white" stroke="black" stroke-width="1"/>
</svg>
```

---

## 7. IMPORTANT VISUAL DETAILS

1. **No anti-aliasing** — `imageSmoothingEnabled = false` and CSS `image-rendering: pixelated`
2. **Body and screen are SAME color** — the original has a "screen" area (rows 2-4) but we paint it the same orange. The eyes are the only contrast.
3. **Eyes are exactly 1 pixel (= 3×3 CSS px)** at columns 3 and 6, row 3
4. **Walking shadow**: when walking, a 1px-wide shadow column appears offset in the walk direction. Color: slightly darker orange. This is optional for web — skip if complex.
5. **Leg alternation creates the walk cycle**: `LEGS_IDLE` (inner legs) → `LEGS_WALK` (outer legs) → repeat. This makes it look like the pet is waddling.

---

## 8. FULL PROMPT FOR ANOTHER CHAT

Copy everything below as a prompt:

---

**Task**: Create a `PtsDockPet.tsx` React component for a Vite+React+TypeScript site at `/Users/3mpq/3mpq-studio-export/`.

Read the full specification from `/Users/3mpq/ClaudeClaw/Web/pts-web-component.md`.

The component renders a pixel-art pet (PTS — Pet in The System) walking along the bottom dock area of the page. It uses HTML Canvas2D to draw a 30×27px pixel sprite at 3x scale.

**Behavior loop** (repeats infinitely):
1. Pet appears at left edge, walks right at 90px/s
2. After 3-5s, a fake macOS cursor fades in at ~60% width
3. Pet stops, looks at cursor (eyes shift)
4. Cursor moves right for 3-4s, pet follows
5. Cursor fades out, pet resumes walking right
6. Pet exits right edge → 30s pause → restart from left

**Key requirements**:
- Pixel-perfect rendering: `imageSmoothingEnabled = false`, `image-rendering: pixelated`
- All pixel data (bodyGrid, legs, colors, eye positions) is in the spec file
- The pet must look identical to the native macOS app (orange body, black eyes, no screen distinction)
- Fake cursor is a CSS div with an inline SVG macOS arrow
- `requestAnimationFrame` for smooth 60fps animation
- DPR-aware canvas for Retina displays
- Container: full-width, ~40-50px tall, `overflow: hidden`
- Place at the bottom of the homepage

Read the spec file for exact pixel grids, draw function, state machine, and timeline.

---

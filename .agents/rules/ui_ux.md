---
trigger: model_decision
description: Use when creating, modifying, or reviewing HUD components, 3D2D displays, Derma windows, menus, tooltips, or any UI/UX features to ensure compliance with GridRP design standards.
---

# GridRP UI/UX & Typography Design System

All HUD components, in-world 3D2D displays, Derma modal dialogs, and interactive prompts must strictly follow these unified design rules.

---

## 0. Foundational Principles: Ben Shneiderman's 8 Golden Rules

Every UI component, interaction model, and visual display in GridRP must align with Ben Shneiderman's 8 Golden Rules of Interface Design:

1. **Strive for Consistency**:
   - Use uniform interaction paradigms, obsidian glassmorphic color schemes, card layouts, standardized font scales, and vocabulary across all menus, HUDs, and 3D2D plates.
   - Key indicators (`[E]`, `[CTRL+E]`, `[F2]`) and close buttons (`"X"`) must be identical in form and behavior everywhere.
2. **Seek Universal Usability**:
   - Accommodate diverse player proficiencies, from first-time rookies entering the dead-drop initiation to veteran syndicate leaders managing turf rackets.
   - Provide clear on-screen prompts for novice players alongside rapid hotkey shortcuts (`F1`-`F4`, `/inv`, quick drag-and-drop) for experienced players.
   - Ensure high text contrast and scalable layouts for diverse display resolutions.
3. **Offer Informative Feedback**:
   - Provide instantaneous, perceptible sensory feedback for every player action (hover brighten, click audio, animated progress bars, sweet-spot needle flashes).
   - Rate limits, validation failures, and cooldowns must trigger explicit visual badges and audio cues rather than failing silently.
4. **Design Dialogs to Yield Closure**:
   - Structure multi-step interactions (crafting fabrication, turf flag captures, lockpicking, recycling batches, printer venting) with a distinct beginning, animated middle, and clear completion banner or signal.
5. **Prevent Errors**:
   - Prevent player mistakes before they happen: gray out unaffordable or level-locked items, disable invalid interaction key triggers, and validate distance server-side.
   - If an error occurs, deliver actionable, constructive guidance (e.g., `"Printer is too hot to pocket (45C)! Allow it to cool below 35C."`).
6. **Permit Easy Reversal of Actions**:
   - Support painless cancellation and reversal wherever feasible (e.g., right-click to cancel lockpicking, [E] toggle to abort searching, Drag-and-Drop return-to-slot on drop failure).
   - Mitigates player anxiety and encourages intuitive exploration.
7. **Keep Users in Control**:
   - Make system behavior predictable and user-initiated. Players should feel in command of their actions rather than disoriented by unexpected pop-ups or jarring camera locks.
   - Windows and dialogs must never trap cursor focus without an obvious `[X]` button, Escape key bind, or background click-out.
8. **Reduce Short-Term Memory Load**:
   - Maintain uncluttered, minimalist displays. Rely on immediate recognition rather than forcing players to memorize numbers or status from other screens.
   - Display relevant context directly where the decision happens (e.g., showing current wallet balance inside the ATM withdrawal menu, or required ingredients checklist directly beside the craft button).

---

## 1. Typography Hierarchy & Scaled Fonts

Never create one-off or hardcoded `surface.CreateFont` sizes in client feature files. Always utilize the calibrated font registry initialized in `GRID.UI.CreateFonts()` (`gamemode/ui/cl_hud.lua`).

| Font Name          | Usage Target                                         | Font & Calibrated Size | Style & Weight        |
| :----------------- | :--------------------------------------------------- | :--------------------- | :-------------------- |
| `GRID_UI_Title`    | Modal banners, level-up titles, close buttons        | 34pt Roboto            | Weight 800 (Heavy)    |
| `GRID_UI_Header`   | Window headers, tooltip item names, major HUD tags   | 25pt Roboto            | Weight 700 (Bold)     |
| `GRID_UI_Sub`      | Subheadings, player nicknames, district banners      | 21pt Roboto            | Weight 600 (Semibold) |
| `GRID_UI_Price`    | Big financial numerals, ATM balances, market prices  | 30pt Roboto            | Weight 800 (Heavy)    |
| `GRID_UI_Btn`      | Interactive button labels, key action prompts        | 20pt Roboto            | Weight 700 (Bold)     |
| `GRID_UI_Body`     | Standard reading copy, item descriptions, dialogs    | 19pt Roboto            | Weight 500 (Medium)   |
| `GRID_UI_BodyBold` | Emphasized descriptions, stat values, inline metrics | 19pt Roboto            | Weight 700 (Bold)     |
| `GRID_UI_Badge`    | Status pills, role tags, compact metric labels       | 16pt Roboto            | Weight 700 (Bold)     |
| `GRID_UI_Caption`  | Fine print, metadata, distance, timestamps           | 17pt Roboto            | Weight 500 (Medium)   |
| `GRID_FontLarge`   | Primary in-world 3D2D metrics ($ stored cash)        | 30pt Roboto            | Weight 800 (Heavy)    |
| `GRID_FontMedium`  | In-world 3D2D headers, entity titles                 | 22pt Roboto            | Weight 700 (Bold)     |
| `GRID_FontSmall`   | In-world 3D2D sub-stats (Temp, Eff, Cooldowns)       | 17pt Roboto            | Weight 700 (Bold)     |
| `GRID_FontAmmo`    | Bottom-right primary & reserve ammo counters         | 42pt Trebuchet MS      | Weight 900 (Black)    |

---

## 2. Obsidian Glassmorphic Color Palette

Always use the standardized dark tactical theme with semi-transparent obsidian surfaces and vivid semantic accents:

### Surfaces & Outlines

- **Primary Modal / Window Background**: `Color(11, 15, 25, 245)` to `Color(15, 23, 42, 245)`
- **Header / Footer Strip Fill**: `Color(17, 24, 39, 255)` (separated by a 1px `Color(30, 41, 59, 255)` line)
- **Sub-Card / List Item / Slot Fill**: `Color(20, 29, 47, 230)` to `Color(30, 41, 59, 240)`
- **Standard Card Border**: `1px` or `2px` with `alpha` between 160-200
- **Top Accent Line**: `3px` or `4px` top bar (`draw.RoundedBoxEx` with `true, true, false, false`)
- **Keycap Box**: `draw.RoundedBox(4, ...)` with subtle background fill (`alpha 60`) and outline (`alpha 200`)

### Semantic Accents (`GRID.Colors`)

- **Success / Cash**: `Color(52, 211, 153)` / `Color(74, 222, 128)`
- **Cyan / Tech / Cyber**: `Color(56, 189, 248)` / `Color(6, 182, 212)`
- **Warning / Alert / Amber**: `Color(245, 158, 11)` / `Color(251, 191, 36)`
- **Danger / Critical / Heat / Health**: `Color(239, 68, 68)` / `Color(248, 113, 113)`
- **Armor / Shield**: `Color(6, 182, 212)` / `Color(34, 211, 238)`
- **XP / Level**: `Color(245, 158, 11)` / `Color(251, 191, 36)`
- **Primary Text**: `Color(248, 250, 252)`
- **Muted Text**: `Color(148, 163, 184)` to `Color(203, 213, 225)`

### Item & Loot Quality Palette (`GRID.Inventory.Quality`)

- **Poor (0)**: `Color(157, 157, 157)`
- **Common (1)**: `Color(248, 250, 252)`
- **Uncommon (2)**: `Color(30, 255, 0)`
- **Rare (3)**: `Color(0, 112, 221)`
- **Epic (4)**: `Color(163, 53, 238)`
- **Legendary (5)**: `Color(255, 128, 0)`

---

## 3. Screen-Space HUD vs. In-World 3D2D Anti-Clutter Rules

1. **Never Render Competing HUDs**:
   - An entity must never render multiple overlapping cards for the same information.
   - If an entity possesses an in-world 3D plate directly on its model (such as money printers or computers), screen-space look-at cards must either be disabled (`InteractionConfig.Enabled = false`) or strictly reserved for transient action minigames (such as the sweet-spot venting needle or lockpicking progress).
2. **Spacing & Padding Standards**:
   - Cards must maintain minimum horizontal padding of `12px` and vertical padding of `8px`.
   - Never squish multi-metric lines into small heights. If an entity shows cash, temp, and efficiency, give each metric dedicated vertical breathing room or arrange them into distinct columns.
3. **Keycap Indicators**:
   - Interactive keycaps (`[E]`, `[CTRL+E]`, `[F2]`) must be rendered inside rounded badge containers with subtle background fills and distinct border outlines, paired horizontally with action descriptions.
4. **Distance & LoS Culling**:
   - All in-world 3D2D elements must cull by distance squared (`DistToSqr`) and perform cached line-of-sight traces (`util.TraceLine`) to avoid rendering through solid walls.
   - All interactive screen-space prompts must fade smoothly using `Lerp` rather than popping in or out abruptly.

---

## 4. Feature-Specific System Architecture

### A. Bottom-Left HUD & Status Bars (`cl_hud.lua`)

- **Dimensions & Anchor**: `346x168px`, anchored bottom-left (`24px` margin from edges).
- **Faction Identity Strip**: 4px left-side accent strip tinted with `GRID.GetGangColor(gangName)` or job faction color.
- **Header Elements**: Level capsule pill (`LVL X`, amber) on left; Gang / Role capsule pill on right; player name in `GRID_UI_Sub` truncated with `GRID.UI.FitText`.
- **Status Bars Track Geometry**:
  - Track height: `14px`, rounded box radius `4px`.
  - Leading label badge: `26x14px` (`HP`, `AP`, `XP`) with `GRID_UI_Badge`.
  - Interpolation: `Lerp(FrameTime() * 10, smoothVal, curVal)` for fluid animation.
  - Text overlay: Centered or right-aligned current/max in `GRID_UI_Badge` with shadow offset.

### B. Inventory & Bag System (`cl_bag.lua`)

- **Container Structure**:
  - Modal Frame: Centered `840x560px` (or scaled), rounded `10px` obsidian frame `Color(11, 15, 25, 252)`.
  - Header: `64px` tall with active container title (`GRID_UI_Header`) and capacity badge (`GRID_UI_Badge`).
  - Footer: `56px` tall with player wallet cash balance and drag/drop instructions.
- **Slot Geometry & Interaction**:
  - Slots: Grid of `64x64px` squares with rounded `6px` sub-card fills `Color(20, 29, 47, 240)`.
  - Quality border: 1–2px outline tinted to item quality color.
  - Hover state: Accent glow border with 40% fill brightening.
  - Drag ghost: Floating `64x64px` icon under mouse cursor with item name and quality border.

### C. F4 Command & Commerce Hub (`cl_f4menu.lua`)

- **Modal Geometry**: `1180x760px` (clamped to 90% screen width/height), centered.
- **Top Bar**: Deep obsidian header with gamemode branding, version pill, player wallet/role pill (`GRID_UI_Header`), and standard 44x44 close button.
- **Left Navigation Sidebar**: `240px` wide, hosting vertical navigation category buttons (`GRID_UI_Btn`, 48px height, active tab cyan indicator strip).
- **Listing Cards**: Sub-cards with 1px border, category badges, requirement checks (`[OK] Requires: Arms Dealer`), and purchase action buttons.

### D. Auction House Two-Tier Tree (`cl_auction.lua`)

- **Modal Geometry**: `1240x780px` centered terminal frame.
- **Two-Tier Browsing Tree**:
  - Left pane (`320px`): Distinct base item hierarchy with market metrics (active listings count, 7-day average, lowest buyout).
  - Right pane: Active individual listings of the selected base item with seller nicknames, durability bars, current bid, and one-click buyout buttons (`GRID_UI_Btn`).
- **Terminal vs. Remote**:
  - Terminal session: Full access (create listings, place bids, instant buyout, claim items).
  - Remote session (cyberphone / radio): Browse-only view with buyouts restricted to in-world terminals.

### E. Crafting Workbench & Resource Fabricator (`cl_crafting.lua`)

- **Modal Geometry**: `980x650px` to `1360x900px` centered workbench frame.
- **Header**: `70px` tall with Resource Fabricator title (`GRID_UI_Title`) and cyan `CRAFTING STATION` badge.
- **Recipe Grid**: Left scrollable pane showing craftable blueprints, tier badges, and machine level requirements.
- **Recipe Inspector**: Right pane displaying result model preview, material ingredient checklist (showing current / required counts with green/red status), and animated fabrication progress bar.

---

## 5. Derma Dialogs, Tooltips & Universal Components

1. **Close Buttons**:
   - Standard top-right close buttons must be `44x44` (or minimum `32x32`), using `GRID_UI_Title` or `GRID_UI_Header` with an ASCII `"X"`, transitioning to `Color(239, 68, 68, 220)` on hover.
2. **Floating Tooltips (`DrawOverlay`)**:
   - Width: Minimum `340px`.
   - Frame: Obsidian `Color(11, 15, 25, 252)` with a 2px outer border tinted to the item's quality color and a 1px inner sub-border `Color(30, 41, 59, 200)`.
   - Title: `GRID_UI_Header` rendered in the item's quality color.
   - Description: Wrapped using `GRID.UI.WrapText` with font `GRID_UI_Body` and line height `22px`.
3. **Pills & Badges**:
   - Height: 20px–24px.
   - Corners: 4px rounded (`draw.RoundedBox(4, ...)`).
   - Text Font: `GRID_UI_Badge` (16pt bold).
   - Fill: Accent color with alpha `35` to `50`; border: accent color with alpha `120` to `160`.
4. **Text Clipping & Truncation**:
   - Never allow labels to overflow cards. Always use `GRID.UI.FitText(text, font, maxW)` for single-line titles/badges and `GRID.UI.WrapText(text, font, maxW)` for paragraphs.

# Output Rules: Strict ASCII Only

Rules:
You must strictly restrict all outputs, code, comments, documentation, and edits to 7-bit ASCII characters (code points 0x00 to 0x7F).

NEVER output any character matching regex: [^\x00-\x7F]
NO smart/curly quotes (' ', " ") -> use standard straight quotes (', ")
NO em/en dashes (—, –) -> use standard hyphens (-, --)
NO bullet glyphs (•, ▪) -> use - or \*
NO emojis (🚀, ✅), degree symbols (°), or unicode arrows (→) -> use text equivalents ([OK], deg, C, F, ->)
If non-ASCII values are required in code, use escape sequences (\xNN, \uNNNN) instead of literal characters.

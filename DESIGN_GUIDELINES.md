# Naked Pantree — Design Guidelines

> Know what you have—no pants required.

This document is the source of truth for Naked Pantree's product voice, visual
identity, and UX personality. It is intentionally opinionated. Restraint is the
point: the humor gets users in, the utility keeps them.

---

## 1. App Overview

**Naked Pantree** helps people track everything in their pantry, fridge,
freezer, and beyond—whether it's in the kitchen, barn, or that extra freezer
outside.

Built for real-life setups (not just perfect kitchens), Naked Pantree lets users:

- 🧊 Track multiple storage locations (indoor + outdoor)
- 🥫 Organize pantry, fridge, freezer, and dry goods in one place
- ⏰ Get alerts before food expires
- 📦 Quickly log and update inventory as they use or restock
- 🔍 Search across all their food instantly
- 🧠 Reduce waste and stop buying duplicates

**Promise:** Simple. Fast. Pants optional.

---

## 2. Brand Positioning

**Core Idea:** *"Serious inventory tracking… that doesn't take itself too
seriously."*

Naked Pantree is a useful system with personality—not a novelty app. Every
design decision should reinforce that hierarchy: **utility first, humor
second.**

### Pillars

| Pillar | What it means |
| --- | --- |
| Practical | Solves a real daily problem (waste, duplicates, expiry). |
| Playful | Light personality in copy, never in core flows. |
| Real-life | Built for messy, multi-location homes—not magazine kitchens. |
| Trustworthy | Data is accurate, alerts are timely, sync is reliable. |

---

## 3. Tone & Voice

- **Playful, but not childish.**
- **Confident, slightly witty.**
- **Never crude or explicit.**
- **Practical-first, humor-second.**

### Voice in practice

✅ Do:

- "You're out of eggs. Again."
- "Milk expires tomorrow. You've been warned."
- "Inventory updated. Productivity achieved (pants optional)."

❌ Don't:

- Crude jokes, innuendo, or anything that earns the name a second time.
- Long-winded copy. If a sentence isn't doing work, cut it.
- Humor inside critical flows (errors, data loss warnings, billing).

### Rule of thumb

If a user is frustrated, hungry, or in a hurry—**be useful, not funny.**
Reserve personality for moments of low stakes (empty states, success toasts,
onboarding).

---

## 4. Logo

Three approved directions, in priority order:

### Concept A — Minimal Icon (Recommended)

- Simple pantry box / crate icon.
- Slight "open door" or "peek inside" visual.
- Clean, modern lines (Apple-style).
- Hidden humor: nothing explicit—the name carries the joke.

### Concept B — Barn + Crate Hybrid

- Small barn silhouette.
- Crate or shelves visible inside.
- Subtle nod to farm / outdoor-storage use case.

### Concept C — The Clever One

- Pantry box with a tiny "missing" lower panel.
- Implies the "no pants" idea without being obvious.
- Use only if a stronger personality cue is wanted.

**Never:** add text inside the logo, use a literal pair of pants, or lean
cartoonish.

---

## 5. Typography

Keep it clean and modern.

| Use | Font |
| --- | --- |
| Primary | San Francisco (iOS default) or **Inter** |
| Alt (more personality) | SF Rounded |

### Wordmark style

Lowercase `naked pantree` works really well. Alternative weighted lockup:

- **Naked** — light weight
- **Pantree** — bold weight

### Hierarchy

- Headings: semibold/bold, tight tracking.
- Body: regular, comfortable line-height (~1.4).
- Numerals (quantities, dates): tabular figures wherever counts or expiry
  dates are listed.

---

## 6. Color Palette

### 🌿 Primary Theme (Farm + Modern)

| Name | Hex | Usage |
| --- | --- | --- |
| Forest Green | `#2F5D50` | Primary brand, headers, key CTAs |
| Warm Cream | `#F4F1EC` | App background, cards |
| Soft Brown | `#8B6F47` | Secondary accents, dividers, pantry category |

### 🧊 Accent Colors

| Name | Hex | Usage |
| --- | --- | --- |
| Cool Blue | `#4A90E2` | Fridge / freezer UI |
| Muted Orange | `#E9A857` | Expiring soon warnings |
| Soft Red | `#D64545` | Expired items, destructive actions |

### Usage rules

- Forest Green is the hero. Don't substitute another green.
- Warm Cream is the canvas. Pure white is reserved for elevated surfaces (e.g.
  modals over cream).
- Status colors (Orange, Red) are reserved for **expiry & destructive
  states**—never decorative.
- Cool Blue is reserved for **cold storage** (fridge, freezer). Don't use it
  for generic links or buttons.

### Accessibility

- Every color pairing in production must meet **WCAG AA** for text contrast.
- Do not communicate state with color alone—pair with an icon or label
  (e.g. expiring items get the orange chip *and* a clock icon).

---

## 7. App Icon

The icon must:

- Look clean on the iOS home screen.
- Not scream "joke app."
- Still feel unique.

### Spec

- Rounded square.
- Deep green (`#2F5D50`) background.
- Minimal white line icon of a crate / pantry box.
- Slight "open" or "peek" visual.
- **No text. No jokes.** Let the name do the work.

---

## 8. Taglines

Use sparingly. One per surface, max.

- "Pants optional inventory."
- "Know what you have."
- "From barn to kitchen."
- "Track everything. Waste less."
- "Check your pantry. Wherever you are."

---

## 9. UX Personality Touches

This is where the brand earns its name. Personality lives in **low-stakes
moments**, not core flows.

| Moment | Copy |
| --- | --- |
| First launch | "Welcome to Naked Pantree. We won't ask what you're wearing." |
| Empty pantry | "Your pantry is empty. This feels like a bigger problem." |
| Expiry warning | "This expires soon. Time to act." |
| Sync success | "All stocked up." |

### Where personality is **off-limits**

- Errors that block the user (auth failure, sync failure, data loss).
- Permission requests (camera, notifications).
- Billing, subscription, and account deletion flows.
- Anything legal, privacy-related, or safety-related.

In those moments: be plain, calm, and direct.

---

## 10. Writing Checklist

Before shipping any user-facing string, ask:

1. Is it **useful** before it's clever?
2. Is it **short**? (Cut a word. Cut another.)
3. Would a frustrated user roll their eyes at it?
4. Does it use color/icon **plus** text for state?
5. Does it reinforce the brand without explaining the joke?

If the answer to any of these is "no," rewrite or remove.

---

## 11. Final Thought

Naked Pantree should be:

- **Useful** — solves a real, daily problem.
- **Sticky** — earns daily check-ins.
- **Memorable** — the name and tone stay with people.

The key is **restraint**. The humor gets them in. The utility keeps them.

# Project: Fantasy Fitness RPG (iOS)

A SwiftUI iOS app that gamifies weightlifting and exercise as a fantasy RPG. The player is an adventurer in a Guild. Real workouts, meals, and sleep are the ONLY source of character power. The game layer (quests, dungeons, loot, ranks) exists to make real effort feel rewarding.

## Core design rules (do not violate)

- Real progress drives in-game power, never the reverse. Loot cannot change real performance; it boosts in-game combat, XP multipliers, quest variants, or cosmetics.
- The client never awards rewards. The app submits raw data (sets, reps, weight, distance, sleep, meals); the server calculates XP, stat gains, and loot.
- Quest objectives complete automatically from logged data. No manual "mark done" checkboxes for workout objectives (prevents cheating).
- Rest days are rewarded (Well-Rested buff), never punished. No stat loss for missed days; use streak freezes and a "welcome back" quest.
- No pay-to-win. Monetization is cosmetics and premium features only.
- Strength rank standards are bodyweight-relative (or DOTS/Wilks), with weight classes for leaderboards. Plate milestones (135/225/315) are separate achievements.
- Nutrition features frame food as fuel. Calorie targets have floors; never generate aggressive restriction quests.

## Tech stack

- Xcode project from the **App** template, SwiftUI, Swift.
- Local storage: **SwiftData** (offline-first; gyms have bad signal). Keep a pending-uploads queue and sync when online. *(Not built yet; the app talks to Supabase directly for now.)*
- Backend: **Supabase** (Postgres, Auth, Storage, Realtime, Edge Functions) via `supabase-swift`.
  - Auth: Sign in with Apple (required if offering other third-party logins), email, Google.
  - Row-level security on every table. Users may insert workouts but may NOT write their own XP, stats, or inventory.
  - XP / stat / loot calculation happens in Postgres functions or Edge Functions.
  - Storage: avatars, recipe photos, later lift-verification videos.
  - Realtime: guild raid boss health.
- HealthKit integration for cardio and sleep. Follow Apple's rules: no ad use of health data, clear privacy policy; prefer keeping raw health data on-device.
- Game visuals (battles) later via SpriteKit embedded with SwiftUI `SpriteView`.

## Backend (Supabase)

Supabase is the backend. Everything the game needs is stored there; the app has no local database yet (the SwiftData offline queue is still to come).

**Files**
- `supabase/migrations/20261022000000_initial_schema.sql`: tables, row-level security, column grants, triggers, server functions, storage buckets.
- `supabase/migrations/20261022000100_catalog_data.sql`: items, dungeons, rank exams, quest templates, starter recipes. Safe to re-run.
- `supabase/migrations/20261101000000_daily_energy.sql`: daily Energy top-up, 4 starting Energy, every dungeon costs 1. Safe to re-run.
- `Fantasy Fitness/Config/Secrets.plist` (gitignored, never commit): `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Copy `Secrets.example.plist` from the repo root to create it. Only the anon/publishable key goes in the app, never the service-role key.
- `Fantasy Fitness/Services/`: `SupabaseConfig.swift` (reads the secrets, builds the client), `Rows.swift` (Codable row types and mapping to models), `GameStore.swift` (the single `@Observable` store all views read from via `@Environment(GameStore.self)`).
- Without a valid `Secrets.plist` the app runs in **offline demo mode** on the sample data in `Models/` (a banner says so); previews use `GameStore.preview`. With keys, every screen shows real data from Supabase; sample data is never shown to a signed-in player.

**Schema**
- Players: `profiles` (name, class, rank, xp, generated `level` / `level_start_xp` / `next_level_xp`, energy, bodyweight, macro targets with a 1200 kcal floor, `has_completed_onboarding`), `stats`, `inventory` (one row per owned item, `equipped`).
- Raw activity (client writes): `workouts`, `workout_sets`, `cardio_logs`, `sleep_logs` (nightly hours only; raw HealthKit stays on device), `meal_logs`. Dates are the player's local date sent by the app.
- Quests: `quest_templates` (server-only), per-player `quests` and `quest_objectives` (metric, target, progress, is_complete).
- Catalogs: `items`, `dungeons`, `rank_exams`. Runs: `dungeon_runs`. Exams: `exam_attempts`.
- Tavern: `recipes`, `recipe_ingredients`, `recipe_ratings` (taste / ease / cost), `recipe_summaries` view.
- `guilds`, `guild_members` (tables only so far). Storage buckets: `avatars`, `recipe-photos`, `lift-videos` (each user writes only under a folder named with their user id).

**Rules the database enforces**
- RLS on every table; players read only their own rows (catalogs and public recipes are shared).
- Column-level grants: players can insert raw data and edit a few profile fields (name, class, bodyweight, macro targets). XP, level, rank, Energy, stats, inventory and quest progress are written only by `security definer` functions.
- New sign-ups get a profile, stats and starter gear from a trigger on `auth.users`.
- Client RPCs: `complete_onboarding`, `generate_quests(p_today)`, `complete_workout`, `equip_item` / `unequip_item`, `start_dungeon_run` / `finish_dungeon_run`, `unlocked_exams`, `create_recipe`. Logging meals, sleep and cardio recomputes quest progress via triggers.
- Stat formulas are placeholders (Strength from best Epley 1RM / bodyweight, Endurance from cardio minutes, Vitality from 7h+ nights) and only ever go up.
- Known gap: dungeon battles are simulated on the device and the client reports victory. Move resolution server-side before anything competitive.

**New account starting values**
- Created by the `on_auth_user_created` trigger: rank F, level 1, 0 XP, **4 Energy** (max 5), all stats 0, starter gear equipped (Iron Helm, Leather Jerkin, Oak Longsword, Copper Ring), default targets 2,400 kcal / 140 g protein / 260 g carbs / 70 g fat.
- No quests until onboarding. `complete_onboarding` saves class, name and bodyweight, then posts the first quests based on the class: a daily (rotates through the class's workouts plus a rest day), a weekly (Forge Week; Rangers get Miles on the Map) and the first four-week story arc (The Iron Trial).

**Daily loop**
- The app calls `generate_quests(p_today)` on every load (sign-in, returning to the app, pull to refresh). Once per local day it tops Energy up to **4** (anything banked above 4 is kept, up to max 5) and posts any missing daily/weekly/story quest. Dates more than a day away from the server's date are rejected.
- Energy: each dungeon run costs **1**. Logging a workout, any cardio, or a 7+ hour night adds 1 (up to max). Sleep of 7+ hours also earns Well-Rested.
- The app mirrors these numbers for display only in `EnergyRules` / `Recovery` (`Models/PlayerProfile.swift`); the server is the source of truth.

**Loading and error states**
- `GameStore.loadState` is `idle / loading / loaded / failed`. Until the first load succeeds, the tab shell shows a full-screen board: "Opening the guild hall…" while loading, or "Can't reach the guild" with Try again / Log out on failure (`Components/BoardStatus.swift`).
- After data has loaded, a failed refresh keeps the last good data on screen and shows a "Couldn't refresh" banner with Retry at the top of each root board. Pull to refresh works on every root board. Sync status also shows in Settings.
- Sign-in only completes once data loads; if it can't, the login sheet shows the reason. Individual writes (equip, log meal, rate, dungeon run) disable their button while saving and show an alert if they fail.

**Setup for a new project**
1. Create a project at supabase.com.
2. Run every file in `supabase/migrations/` in name order (SQL Editor, or `supabase link` + `supabase db push`).
3. Put the Project URL and anon key in `Config/Secrets.plist`.
4. Auth providers: Email is on by default. Apple needs the bundle ID `com.appteamcarolina.Fantasy-Fitness` under Client IDs plus the Sign in with Apple capability in Xcode. Google needs a Google Cloud OAuth client. Add `fantasyfitness://login-callback` under Authentication → URL Configuration → Redirect URLs.

## Game systems

**Stats:** Strength (compound lifts, PRs, volume), Endurance (cardio duration/volume), Speed (pace, sprint times), Agility (plyometrics, drills), Vitality (sleep consistency, protein/calorie targets), optional Flexibility (mobility).

**Level vs stats:** Level = total XP (consistency). Stats = capability (only rise when real performance rises).

**Classes:** Warrior (strength), Ranger (endurance), Monk (calisthenics), Paladin (hybrid). Class sets default routine and bonus XP.

**Core loop:** Train → Grow (level, stats, unlock exams) → Fight (dungeons/bosses, costs Energy) → Loot → Train. Every day starts with 4 Energy; each dungeon run costs 1; real activity and sleep add more.

**Quests:** generated from the chosen program. Types: Daily, Weekly, Story (multi-week arcs tied to a program block, include deloads), Side. Each covers training, nutrition, and recovery.

**Ranks:** Guild ranks F → E → D → C → B → A → S. Each requires exams across stats (e.g., D-rank bench = 1.0× bodyweight). Passing grants badge, title, unique gear, new dungeon tiers. Exams include warm-up protocol and spotter prompt for bench.

**Loot rarity:** Common → Uncommon → Rare → Epic → Legendary. Gear never counts toward exams.

**Tavern (food):** meal library with macros (USDA FoodData Central / Open Food Facts), recipe creator with auto macros, barcode scanner, meal logging feeding nutrition quests. Ratings on separate axes: taste, ease, cost, macro profile (auto).

**Later:** pose-estimation lift verification (MediaPipe/MoveNet: ROM, rep count, form flags; weight verification via video + community/friend review first), async PvP by rank and weight class, guild raids, stat-driven avatar evolution (body-composition avatar must be opt-in and never shaming).

## Navigation map

App shell: `TabView` with a `NavigationStack` per tab. Title screen and onboarding sit outside it, gated by a `hasCompletedOnboarding` flag.

- **Title screen** → New game → **Onboarding** (class, goals, program) → Guild Hall
- **Title screen** → Continue → **Guild Hall**
- **Settings** (profile, sync, units) reachable from Title and Guild Hall

Tabs:
1. **Guild Hall** (home hub: today's quests, Energy, unlocked exams)
2. **Quests**: Quest board → Workout session → Quest complete → Loot reveal
3. **Character**: Character sheet → Inventory → Item detail → Equip/compare
4. **Dungeons**: Dungeon map → Loadout → Battle → Loot reveal
5. **Tavern**: Meal library → Recipe detail → Log meal → Rate recipe; Create recipe opens as a sheet

Notes:
- **Loot reveal** is shared by Quests and Dungeons: build once as a reusable view/modal.
- **Workout session** and **Battle** are presented with `.fullScreenCover` (tab bar hidden).
- **Rank exams** appear as a card on the Quest board and launch Workout session in "exam mode."
- Quest board "Begin quest" button opens Workout session (log weight/reps per set, rest timer) → Quest complete (XP, stat gains) → Loot reveal. Label varies by tab: Daily "Begin quest"; Weekly and Story "Log a workout" (their progress shows on the scroll). The Guild Hall also has a "Log a workout" button.

**Workout session** (`Views/Workout/`)
- `WorkoutSession` (state) + `WorkoutSessionView` (UI), presented with `.workoutSessionCover($activeWorkout)`. A daily quest opens with its lifts as the plan (exercise, sets, min reps / weight from `quest_objectives`); other entry points open a free session. "Add" adds any exercise.
- The big title is the current exercise and slides to the new name whenever it changes: tapping an exercise chip, adding one, or finishing the last required set of a lift (auto-advances to the next unfinished lift).
- Log set = weight × reps (steppers, prefilled from the last set or the quest minimum). Sets below the quest minimum are still logged but marked as not counting.
- Rest timer (`RestTimerCard` / `RestTimer`) starts automatically after every logged set: ring countdown, −15 s / pause / +30 s / skip, preset lengths 1:00–3:00 (default 1:30), haptic when it ends. It stores an end time, so it stays correct in the background.
- Nothing is sent until **Finish workout**: inserts `workouts` + `workout_sets`, then `complete_workout` returns XP; the store reloads so quest progress, stats and Energy update. Closing with unsaved sets asks to discard.

## Visual style (Quest Board reference)

Blend of realistic rustic (wood plank board, brass pins, aged parchment) and cartoon (thick brown outlines, flat warm fills, rolled scroll ends with wooden knobs, hard drop shadows). Readability first.

Fonts:
- Title only: **Pirata One** (blackletter)
- Headings / quest names / buttons: **Alegreya** (700–800)
- Body / objectives / numbers: **Alegreya Sans** (400–700)

Colors:
- Wood: base `#7A4B2A`, plank seams `rgba(38,18,6,.6)`, dark wood `#5A3418`, darkest `#3A2008` / `#241204`
- Parchment: `#F4DFAE` (scroll), `#F1D9A2` (notes), scroll rolls `#E2B565`, knobs `#8A4B1C`
- Outline brown: `#5C3412`; ink text `#3B2412`; secondary text `#6B4423`; kicker `#8A4B1C`
- Gold (title, active tab/nav): `#F2C14E`
- Wax seal / primary button accent: `#A3341F` with border `#4A1A0E`, text `#FFF3D6`
- Progress / completed green: `#6E8B3D`; positive text `#3F5A1E`
- Brass pins: `#C9962E`

Quest Board layout (top to bottom): Level/rank pill + Energy pill; wooden sign with "Quest Board" title; Daily / Weekly / Story tabs; featured quest on a cartoon scroll (kicker, title, wax seal icon, progress bar, objectives, reward chips, primary button); pinned notes grid (Ration duty protein progress, Rest at the inn sleep goal, full-width Guild notice for unlocked exam); bottom tab bar on dark wood. Touch targets ≥ 44 pt.

## Roadmap

- **MVP (v0.1):** accounts, class selection, workout logging with 3–4 preset programs, stats and leveling, daily/weekly quests, basic cosmetic loot, one simple dungeon.
- **v0.5:** rank exams (bodyweight-relative), nutrition logging and basic Tavern, HealthKit/wearable sync, guilds with shared raid bosses.
- **v1.0:** full dungeon/boss system, video verification with community review, gear with XP modifiers.
- **Future:** pose-estimation verification, async PvP and seasonal arenas, avatar evolution.

## Open questions

- Daily time spent in the game layer (target ~5 minutes)
- Combat: skill-based or purely stat-based
- Balancing lifters vs. runners across classes
- Inactivity: stats plateau (preferred) vs. decay
- Art style (pixel art is cheapest)

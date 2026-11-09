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
- Local storage: **SwiftData**, offline-first because gyms have bad signal. See "Offline-first data" below.
- Backend: **Supabase** (Postgres, Auth, Storage, Realtime, Edge Functions) via `supabase-swift`.
  - Auth: Sign in with Apple (required if offering other third-party logins), email, Google.
  - Row-level security on every table. Users may insert workouts but may NOT write their own XP, stats, or inventory.
  - XP / stat / loot calculation happens in Postgres functions or Edge Functions.
  - Storage: avatars, recipe photos, later lift-verification videos.
  - Realtime: guild raid boss health.
- HealthKit integration for cardio and sleep. Follow Apple's rules: no ad use of health data, clear privacy policy; prefer keeping raw health data on-device.
- Game visuals (battles) later via SpriteKit embedded with SwiftUI `SpriteView`.

## Architecture

The target, for all new code:

- MVVM with `@Observable`, but only screens with real logic get a view model.
- Some view models cover a whole flow, e.g. workout, quest complete, rank exam.
- A small `AppSession` holds the global state: profile, stats, Energy.
- Game rules live in services, to make testing easier. Anything that affects rewards stays on the server (Postgres functions); app-side rules only mirror it for display.
- Files are grouped by feature, one folder per tab.

Where the code is today:

- **View model:** `WorkoutSession` covers the workout flow, including quest complete. It's the model for new flows; `BattleSession` covers a dungeon fight the same way. Other screens use `GameStore` plus local `@State`.
- **Services:** `SyncService` (uploads and refresh), `SleepService` (sleep check-in) and `FoodService` (food search), all owned by `GameStore` and read as `store.sync` / `store.sleep` / `store.food`.
- **`GameStore`:** plays the `AppSession` role but is larger than intended. It also holds each tab's data, sign-in, connection-only actions and snapshot mapping.
- **Rules:** XP, loot and quest rules are in Postgres. Display copies are `EnergyRules` and `Recovery` (`Models/PlayerProfile.swift`) and `GuildRank` (`Services/Rows.swift`). Battle rules are app-side in `Services/BattleRules.swift`, because fights are still decided on the phone (see the known gap below).
- **Folders:** `Views/` has one folder per tab; `Models/`, `Services/` and `Components/` are shared.

Moving toward the target, without a big rewrite:

- New flows (rank exam, cardio) get their own view model or service, as sleep and food search did (`SleepService`, `FoodService`), instead of adding to `GameStore`.
- Shrink `GameStore` toward `AppSession` when already working in that area.
- Move the display rules into a service when they next change.

## Backend (Supabase)

Supabase is the backend and the source of truth for anything that affects rewards. The app keeps a local copy and a pending-uploads queue (see "Offline-first data").

**Files**
- `supabase/migrations/20261022000000_initial_schema.sql`: tables, row-level security, column grants, triggers, server functions, storage buckets.
- `supabase/migrations/20261022000100_catalog_data.sql`: items, dungeons, rank exams, quest templates, starter recipes. Safe to re-run.
- `supabase/migrations/20261101000000_daily_energy.sql`: daily Energy top-up, 4 starting Energy, every dungeon costs 1. Safe to re-run.
- `supabase/migrations/20261106000000_offline_sync.sql`: retry-safe `submit_workout` and `log_meal`. Safe to re-run.
- `supabase/migrations/20261107000100_item_combat_bonuses.sql`: `items.attack_bonus` / `defense_bonus` for battles. Safe to re-run.
- `supabase/migrations/20261107000000_sleep_check_in.sql`: `log_rested_night(p_night_of)`, the sleep check-in. Safe to re-run.
- `supabase/migrations/20261108000000_food_data.sql`: `foods`, `log_food_meal`, `create_recipe` working out macros from searched ingredients, and players can no longer write meal macro columns. Safe to re-run.
- `supabase/functions/`: Edge Functions (Deno). `food-search` looks foods up on USDA FoodData Central; shared code and its tests are in `_shared/` (see "Edge Functions" below).
- `Fantasy Fitness/Config/Secrets.plist` (gitignored, never commit): `SUPABASE_URL` and `SUPABASE_ANON_KEY`. Copy `Secrets.example.plist` from the repo root to create it. Only the anon/publishable key goes in the app, never the service-role key.
- `Fantasy Fitness/Services/`: `SupabaseConfig.swift` (reads the secrets, builds the client), `Rows.swift` (Codable row types and mapping to models), `LocalStore.swift` (SwiftData models and on-device storage), `SyncService.swift` (upload queue and refresh), `SleepService.swift` (sleep check-in), `FoodService.swift` (food search), `GameStore.swift` (the single `@Observable` store all views read from via `@Environment(GameStore.self)`).
- Without a valid `Secrets.plist` the app runs in **offline demo mode** on the sample data in `Models/` (a banner says so); previews use `GameStore.preview`. Demo data lives in memory only. With keys, every screen shows real data from Supabase or its local copy; sample data is never shown to a signed-in player.

**Schema**
- Players: `profiles` (name, class, rank, xp, generated `level` / `level_start_xp` / `next_level_xp`, energy, bodyweight, macro targets with a 1200 kcal floor, `has_completed_onboarding`), `stats`, `inventory` (one row per owned item, `equipped`).
- Raw activity (client writes): `workouts`, `workout_sets`, `cardio_logs`, `sleep_logs` (nightly hours only; raw HealthKit stays on device), `meal_logs`. Dates are the player's local date sent by the app.
- Quests: `quest_templates` (server-only), per-player `quests` and `quest_objectives` (metric, target, progress, is_complete).
- Catalogs: `items` (`attack_bonus` / `defense_bonus` are the battle numbers; new gear must set them to match its `effect` text), `dungeons`, `rank_exams`. Runs: `dungeon_runs`. Exams: `exam_attempts`.
- Tavern: `recipes`, `recipe_ingredients`, `recipe_ratings` (taste / ease / cost), `recipe_summaries` view.
- Food data: `foods` holds per-100 g kcal / protein / carbs / fat, copied from USDA by the Edge Functions (`source = 'usda'`, keyed by `fdc_id`; an `'estimate'` row belongs to the player in `created_by`). Players can't read or write it directly; they get food data from the functions. A searched recipe ingredient has `food_id` + `grams`; a plate meal keeps its `[{food_id, grams}]` in `meal_logs.items`.
- `guilds`, `guild_members` (tables only so far). Storage buckets: `avatars`, `recipe-photos`, `lift-videos` (each user writes only under a folder named with their user id).

**Rules the database enforces**
- RLS on every table; players read only their own rows (catalogs and public recipes are shared).
- Column-level grants: players can insert raw data and edit a few profile fields (name, class, bodyweight, macro targets). XP, level, rank, Energy, stats, inventory and quest progress are written only by `security definer` functions.
- New sign-ups get a profile, stats and starter gear from a trigger on `auth.users`.
- Client RPCs: `complete_onboarding`, `generate_quests(p_today)`, `submit_workout`, `log_meal`, `log_food_meal`, `log_rested_night`, `equip_item` / `unequip_item`, `start_dungeon_run` / `finish_dungeon_run`, `unlocked_exams`, `create_recipe`. Logging meals, sleep and cardio recomputes quest progress via triggers. `complete_workout` remains for older builds; `submit_workout` calls it internally.
- Meal macros always come from server data, because daily protein completes weekly quests: `log_meal` copies them from the recipe, and `log_food_meal(p_id, p_name, p_items, p_eaten_on)` sums `foods` × grams. Players can't write the macro columns of `meal_logs` or `recipes`. `create_recipe` (security definer) works out per-serving macros from the searched ingredients; typed-in ones are saved but not counted, and with none the macros stay null ("Macros pending").
- Known gap: per-serving macros are fixed when a recipe is created, but players can still update `recipes.servings`. A recipe editor must go through an RPC that recomputes.
- Stat formulas are placeholders (Strength from best Epley 1RM / bodyweight, Endurance from cardio minutes, Vitality from 7h+ nights) and only ever go up.
- Known gap: dungeon battles are simulated on the device and the client reports victory. Move resolution server-side before anything competitive. The battle engine is seeded from the run id and has no app dependencies, so the server could later replay a fight from the seed and the player's inputs.

**New account starting values**
- Created by the `on_auth_user_created` trigger: rank F, level 1, 0 XP, **4 Energy** (max 5), all stats 0, starter gear equipped (Iron Helm, Leather Jerkin, Oak Longsword, Copper Ring), default targets 2,400 kcal / 140 g protein / 260 g carbs / 70 g fat.
- No quests until onboarding. `complete_onboarding` saves class, name and bodyweight, then posts the first quests based on the class: a daily (rotates through the class's workouts plus a rest day), a weekly (Forge Week; Rangers get Miles on the Map) and the first four-week story arc (The Iron Trial).

**Daily loop**
- The app calls `generate_quests(p_today)` at the start of every sync, before uploading, so a workout logged offline counts toward today's quests. Once per local day it tops Energy up to **4** (anything banked above 4 is kept, up to max 5) and posts any missing daily/weekly/story quest. Dates more than a day away from the server's date are rejected.
- Energy: each dungeon run costs **1**. Logging a workout, any cardio, or a 7+ hour night adds 1 (up to max). Sleep of 7+ hours also earns Well-Rested.
- Sleep (until HealthKit): the player ticks "Slept 7+ h" (Guild Hall, Quest board note), confirms once, and can't undo it. `log_rested_night` records that night (yesterday's local date) as exactly 7 hours, so the existing `after_sleep_logged` trigger pays Energy, Vitality and quest progress. One row per night, so repeats change nothing. Not checking is never punished.
- The app mirrors these numbers for display only in `EnergyRules` / `Recovery` (`Models/PlayerProfile.swift`); the server is the source of truth.

**Offline-first data**

The app reads from and writes to the device, and syncs with Supabase in the background. Three kinds of data, three rules:

| Kind | Examples | Rule | Where |
|---|---|---|---|
| Created by the user | Workouts, sets, meal logs, plates of searched foods, sleep check-ins (later: exam attempts, cardio) | Write locally first, queue for upload, never lost offline | `LocalWorkout`, `LocalSet`, `LocalMeal`, `LocalPlateMeal`, `LocalSleep` |
| Owned by the server | Profile, stats, XP, inventory, quests, catalogs, recipes | Cache for instant display, refresh from the server, server always wins | `CachedSnapshot` |
| Network only | Gear, dungeon runs, creating or rating recipes, food search (later: leaderboards, forum, PvP, raids) | Needs a connection; offline shows "You're offline" | Direct calls in `GameStore`; food search in `FoodService` |

- **Who talks to Supabase:** views never do. `SyncService` owns uploads and refreshes. `GameStore` owns auth and the network-only actions, and turns snapshots into the models views read. `FoodService` calls the food-search Edge Function.
- **Snapshot cache:** server-owned data is one JSON `ServerSnapshot` per player, replaced whole by each refresh. It's not split into SwiftData tables because the app never queries or edits it, and an undecodable snapshot is just an empty cache. Dated data is rechecked when shown: quests past `ends_on` are hidden, meals count only on the fetch day, sleep only for last night.
- **Launch:** a saved session plus a local snapshot opens the app immediately, even offline, then refreshes quietly. The first sign-in on a device still needs a connection.
- **During a workout:** each set is saved to SwiftData the moment it's logged. The workout is created with its first set; `finishedAt == nil` means in progress. After a crash, or "Keep for later", the Guild Hall and Quest board offer "Resume workout" (one unfinished workout at a time).
- **Finishing:** the workout joins the queue and the app waits up to 8 seconds for an upload. If the server answers, the summary shows the real payout. If not, it shows "Rewards pending". After a later upload, `ContentView` presents the loot reveal, held back while a workout or battle is on screen (`holdsRewardReveals`).
- **Meals:** count toward today's rations immediately as a display-only copy. They stay on the device after upload until a refresh includes them, so the numbers don't dip. Plates (`LocalPlateMeal`, a separate model so the existing store opens without a migration) work the same way; the server sums their real macros from `foods`.
- **Sleep check-ins:** same pattern as meals. The check shows right away and stays until a refresh includes the server's row.
- **Sync triggers:** app open or foreground, connection back (`NWPathMonitor`), workout, meal or sleep check-in saved, pull to refresh. Requests during a pass fold into one more pass.
- **Each pass:** `generate_quests`, upload workouts, upload meals and plates, upload sleep check-ins, fetch and save the snapshot. No connection stops the pass and keeps everything queued. A server refusal skips only that log, keeps it, shows the reason and retries next sync, so one bad log can't block the rest.
- **Logout:** tries to upload first. Anything left stays on the device, tied to that player, and uploads at their next login. Only their cached snapshot is deleted.

Rules that prevent sync bugs:
- **Ids come from the phone.** Workouts, sets and meals get a UUID on the device (a sleep check-in is keyed by player and night instead). `submit_workout` is one transaction; a repeat of the same id pays nothing and returns the stored result, so flaky Wi-Fi can't double XP.
- **Logs are add-only.** Sync never edits a workout or meal, so devices can't overwrite each other.
- **Never calculate rewards locally.** The app sends raw sets; the server returns XP (`xp_gained`, including quests the workout completed) and loot (`item_ids`). Demo mode's estimate is the only exception, because it has no server.
- **Offline logs have a date limit:** the server accepts dates from 30 days ago to tomorrow.
- **Client limits must match server limits**, or a log is refused forever (exercise name up to 80 characters, weight up to 2,000 lb; a plate has 1–30 foods of 1–2,000 g each; a recipe has up to 40 ingredients of 1–5,000 g and 1–50 servings). Food limits live in `FoodLimits` (`Models/Food.swift`). Meal and ingredient names are cut to 80 characters by the server rather than refused.

Other storage:
- Login session: `supabase-swift` stores it. Keep any other secrets in the Keychain, not SwiftData or `UserDefaults`.
- Small preferences (units, last tab): `@AppStorage`.
- HealthKit: read on the device and upload only the summaries quests need (e.g. "slept 7.5 hours"), not raw records.

**Edge Functions** (`supabase/functions/`, Deno)
- `food-search`: `POST {"query", "limit"}` → `{"foods": [{id, source, name, detail, per_100g, portions}]}`. Searches USDA FoodData Central (Foundation, SR Legacy and Survey (FNDDS) foods; no branded foods), saves every result to `foods` with the service role, and returns the row ids, so the app can put a food straight into a recipe or plate.
- Every function checks the caller's session itself (`_shared/auth.ts`), because it writes with the service role. Errors come back as `{"error": {"code", "message"}}`; `ServerError.message` shows the message as-is, so write it for the player.
- USDA's top hit can be wrong ("banana" returns dehydrated banana first), so the search shows kcal and protein per 100 g and the player picks. Nothing is picked automatically.
- Pure logic (normalizing USDA data, energy fallbacks, portions) has Deno tests with saved USDA responses: `deno test --allow-read=supabase/functions supabase/functions/`. Imports are pinned `npm:` / `jsr:` versions; there is no import map.
- Never log request bodies or USDA URLs (the API key is in the query string).

**Loading and error states**
- `GameStore.loadState` is `idle / loading / loaded / failed`. With no local copy yet, the tab shell shows a full-screen board: "Opening the guild hall…" while loading, or "Can't reach the guild" with Try again / Log out on failure (`Components/BoardStatus.swift`).
- With data on screen, root boards show a banner when needed: offline (with what's waiting to upload), "Couldn't refresh" after a server error, or a refused upload. Each has Retry. Pull to refresh works on every root board. Settings shows sync status, the queue and the last sync.
- Sign-in only completes once data loads; if it can't, the login sheet shows the reason. Network-only actions disable their button while saving and show an alert if they fail.

**Setup for a new project**
1. Create a project at supabase.com.
2. Run every file in `supabase/migrations/` in name order (SQL Editor, or `supabase link` + `supabase db push`).
   - Pick one way and stick to it. Supabase's GitHub integration (and `db push`) tracks applied files in `supabase_migrations.schema_migrations`. A file run by hand in the SQL Editor isn't recorded there, so the integration tries to run it again and fails (e.g. `type "guild_class" already exists`). After running one by hand, record it: `insert into supabase_migrations.schema_migrations (version, name) values ('<timestamp>', '<name>') on conflict do nothing;`
   - Every migration needs a unique timestamp. Supabase identifies a file by the number before the underscore only, so two files with the same number clash (`duplicate key ... schema_migrations_pkey`) and the second never runs. Before adding a file, check the newest number in `supabase/migrations/` (on an up-to-date `main`) and use a later one.
3. Put the Project URL and anon key in `Config/Secrets.plist`.
   - Edge Functions: get a free FoodData Central key at api.data.gov, then `supabase secrets set USDA_API_KEY=<key>` and `supabase functions deploy food-search`. Without the key it falls back to USDA's `DEMO_KEY`, which allows only a few searches an hour.
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
5. **Tavern**: Meal library → Recipe detail → Log meal → Rate recipe; Log a meal and Create recipe open as sheets

Notes:
- **Loot reveal** is shared by Quests and Dungeons: build once as a reusable view/modal.
- **Workout session** and **Battle** are presented with `.fullScreenCover` (tab bar hidden).
- **Rank exams** appear as a card on the Quest board and launch Workout session in "exam mode."
- Quest board "Begin quest" button opens Workout session (log weight/reps per set, rest timer) → Quest complete (XP, or rewards pending offline) → Loot reveal when the server granted loot. Label varies by tab: Daily "Begin quest"; Weekly and Story "Log a workout" (their progress shows on the scroll). The Guild Hall also has a "Log a workout" button.

**Logging meals** (`Views/Tavern/LogMealSheet.swift`)
- "Log a meal" (Tavern, under today's rations) and "Log meal" (Guild Hall, Ration duty row) open a sheet listing the meal library by meal type. Picking one fills in its nutrition (one serving: kcal, protein, carbs, fat) above the Log button. Logging saves it on the device (`GameStore.logMeal`); the server refills the real macros from the recipe. Recipe detail still has its own Log meal button.
- "Build a plate from foods" at the top opens `PlateSheet`: add each food from the food search (`FoodSearchSheet`), set grams with `GramsEditor` (type, − / +, or tap a USDA portion like "1 cup, cooked · 158 g"), swap or remove foods, name the meal (it suggests one), and log. `GameStore.logPlate` saves it on the device; the totals shown are a preview until the server's arrive.

**Creating recipes** (`Views/Tavern/RecipeSheets.swift`)
- Name, meal type, servings (1–50), then ingredients. "Add ingredient" opens the food search; a searched food gets grams and counts toward the macros, and "Add "…" without nutrition" keeps a typed-in ingredient that isn't counted. A live "Per serving" preview says how many ingredients count. The server computes the saved macros, and recipe detail marks typed-in ingredients "not counted".

**Workout session** (`Views/Workout/`)
- `WorkoutSession` (state) + `WorkoutSessionView` (UI), presented with `.workoutSessionCover($activeWorkout)`. A daily quest opens with its lifts as the plan (exercise, sets, min reps / weight from `quest_objectives`); other entry points open a free session. "Add" adds any exercise.
- The big title is the current exercise and slides to the new name whenever it changes: tapping an exercise chip, adding one, or finishing the last required set of a lift (auto-advances to the next unfinished lift).
- Log set = weight × reps (steppers, prefilled from the last set or the quest minimum). Sets below the quest minimum are still logged but marked as not counting.
- Rest timer (`RestTimerCard` / `RestTimer`) starts automatically after every logged set: ring countdown, −15 s / pause / +30 s / skip, preset lengths 1:00–3:00 (default 1:30), haptic when it ends. It stores an end time, so it stays correct in the background.
- Each set is saved on the device as it's logged. **Finish workout** queues it for `submit_workout`; the refresh updates quest progress, stats and Energy. Closing with sets asks whether to keep the workout for later or discard it. See "Offline-first data" for the pending and reward flow.

**Battle** (`Views/Dungeons/`)
- `BattleSession` (state) + `BattleView` (UI), presented from Loadout with `.fullScreenCover`. The engine is `BattleState` in `Services/BattleRules.swift`: Foundation only, seeded from the run id, so it can be simulated, tested or moved to the server. Still SwiftUI; a later SpriteKit scene can drive the same engine.
- Each turn: the boss shows its next move (Swipe, Heavy swing, Bracing; Enraged below 30% health) → the player picks Strike, Heavy Blow, Guard or the class skill (Warrior Cleave, Ranger Volley, Monk Flurry, Paladin Smite; every 3 turns) → attacks are aimed on the timing meter (gold = critical, green = hit, outside = glancing) → the boss acts.
- Real stats set the numbers: Health = 100 + Vitality + Endurance/2, Attack = 10 + Strength/4 + gear, Defense = gear; Agility widens the gold zone and Speed slows the meter. Timing only scales a hit between 0.5× and 1.3×, so it can't stand in for training. Loadout shows where each number comes from.
- Every tuning number is at the top of `BattleRules`. Balance was checked by simulating thousands of fights per dungeon for a new player, the demo player and a strong lifter; re-check after changing them.
- Win → `finish_dungeon_run(victory: true)` → Loot reveal. If claiming fails, the player can try again (the run stays open on the server). A loss, or fleeing (which asks first, since Energy is already spent), reports `victory: false`. The winning blow stays on screen for 1.4 s before the chest, even when the server answers at once.
- Layout and motion: the cards must not move between steps, so hidden copies of the action buttons and the meter size the controls, and the boss's move chip keeps its space when the fight ends. Changing text (log line, next move) fades out before the new text fades in; HP and turn numbers roll. The arena scrolls only with large text (starting at the bottom, so actions stay in reach), and actions stack in one column at accessibility sizes.

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
- Combat: for now stat-based turns plus a timing meter that only nudges damage (see Battle); revisit before PvP
- Balancing lifters vs. runners across classes
- Inactivity: stats plateau (preferred) vs. decay
- Art style (pixel art is cheapest)

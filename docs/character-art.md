# Character art guide

The character is a "paper doll": a stack of transparent images, all the same size, drawn on top of each other. The body is drawn once, and every hairstyle and item is its own image. The app picks the layers for the player's look and gear and stacks them.

Until an image exists, the app draws a simple placeholder in its place. You can add art one file at a time, and each new file replaces its placeholder right away with no code changes.

## The one rule

**Every layer uses the same canvas, with the character in the same spot.**

A helm is a full-canvas image that's mostly transparent, with the helm drawn exactly where the head is. Never crop a layer to its contents, and never move the character between files.

- **Canvas:** square, **1024 × 1024 px**. Export PNG with transparency. (Or vector PDF in the same square, with "Preserve Vector Data" turned on in Xcode.)
- **Pose:** front facing, arms at the sides, weapon held in the hand on the viewer's right.
- **Template:** open `Views/Character/CharacterView.swift` in Xcode and look at the **"Art template"** preview. It shows the placeholder body on a 10 × 10 grid. Screenshot it, scale it to 1024 × 1024, and put it on a locked bottom layer in your drawing app. Each grid square is 102.4 px.

Key positions (out of 100, across and down):

| Part | Position |
|---|---|
| Head | circle centered at (50, 30), radius 13 |
| Neck | y 41–47 |
| Torso | y 45–72; x 37–63 (narrow frame) or 33–67 (broad frame) |
| Hands | (32.5, 73) and (67.5, 73) narrow; (28.5, 73) and (71.5, 73) broad |
| Feet | bottom at y 96 |

You don't have to match the placeholder's proportions. Once you replace the body, though, every other layer has to line up with **your** body. So draw the base body first and agree on it before anyone draws gear.

## Files and names

Put each image in `Fantasy Fitness/Assets.xcassets/Character/` (drag it in in Xcode). **The image set's name must match exactly**, all lowercase:

| Layer | Name | Notes |
|---|---|---|
| Body | `body_narrow`, `body_broad` | Skin only. **Draw it in light grays**; the app colors it with the chosen skin tone. |
| Starting clothes | `outfit_narrow`, `outfit_broad` | Tunic, trousers, boots. In full color. |
| Face | `face` | Eyes, brows and mouth only. In full color, shared by both frames. |
| Hair | `hair_short`, `hair_long`, `hair_braid`, `hair_topknot` | **Light grays**, colored by the chosen hair color. `shaved` has no file. |
| Hair behind the body | `hair_long_back` (any style, `hair_<style>_back`) | Optional. The part of long hair that hangs behind the shoulders. |
| An item | `item_<item id>` | The id is from the database, e.g. `item_iron-helm`, `item_war-hammer`. |
| An item for one frame | `item_<item id>_narrow`, `item_<item id>_broad` | Optional. Used instead of `item_<id>` for that frame (useful for chest armor). |
| An item's back part | `item_<item id>_back` | Optional. A cape, the back of a hood, a blade held behind the body. |

Item ids (from `supabase/migrations/20261022000100_catalog_data.sql`):

- **Head:** `iron-helm`, `moss-hood`, `ranger-cowl`, `wyrm-helm`, `crown-of-iron`
- **Chest:** `leather-jerkin`, `studded-vest`, `chainmail`, `gilded-plate`
- **Weapon:** `oak-longsword`, `ash-spear`, `war-hammer`, `rune-axe`
- **Trinket:** `copper-ring`, `ember-charm`, `restful-amulet`, `tide-pendant`

## Stacking order (back to front)

1. Hair behind the body (`hair_<style>_back`)
2. Back parts of gear (`item_<id>_back`)
3. Body (tinted with skin tone)
4. Starting clothes
5. Face
6. Chest item
7. Trinket
8. Hair (tinted with hair color)
9. Head item
10. Weapon

## Coloring skin and hair

The app colors the body and hair images by **multiplying** them with the chosen color:

- **White** becomes exactly the chosen color.
- **Light gray** becomes a shade of it, which is good for shading.
- **Black** stays black, so outlines stay dark.

So draw skin and hair in white-to-light-gray with dark outlines, and the eight skin tones and eight hair colors all come from that one drawing. Don't put eyes, clothes or anything else that shouldn't be tinted on these layers; they go on `face` and `outfit`.

The color lists are in `Models/Appearance.swift` (`skinTones`, `hairColors`).

## Helmets and hair

Most head items hide the hair completely, so hair never pokes through a helmet. Head items that leave hair visible, like crowns, are listed in `CharacterArt.headItemsShowingHair` (`Views/Character/CharacterView.swift`). Add an item's id there if it should show the hair under it.

## Adding a new hairstyle, frame or item

- **New item:** add it to the database as usual, then add `item_<id>`. The app needs no other changes.
- **New hairstyle:** add a case to `HairStyle` in `Models/Appearance.swift` (the case name is the file name: `case mohawk` uses `hair_mohawk`). Add a placeholder drawing in `CharacterPlaceholder.hairFront` or skip it. No database change is needed.
- **New frame:** add a case to `BodyType`, draw `body_<frame>` and `outfit_<frame>`, and check every chest item on it.

## Checking your art

Build and run the app, then look at:

- **Character tab:** the full character, plus **Customize** to try every skin tone, hairstyle and hair color.
- **Item detail → "Try it on":** any item on the character, even one that isn't equipped.
- **The Xcode previews** in `CharacterView.swift` and `AppearanceEditorView.swift`.

If an image doesn't show up, check its name in the asset catalog. A misspelled name silently falls back to the placeholder.

If the art is pixel art, set `CharacterArt.isPixelArt = true` so it scales without blurring.

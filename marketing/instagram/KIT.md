# NAGISEN on Instagram

Dark mystery, elegant minimalism. Bodies in motion, never faces, never app screenshots.
Audience: Morocco. All captions and on-image text in English.

## Profile

- **Name field:** NAGISEN · Quiet progress
- **Username:** @nagisen (or @nagisen.app if taken)
- **Picture:** the app icon (`Daywell/Assets.xcassets/AppIcon.appiconset/AppIcon-dark.png`)
- **Bio** (under 150 characters):

  ```
  The art of quiet progress.
  Nutrition · movement · habits.
  ↓ Open NAGISEN
  ```
- **Link:** https://ahmedkhalildaoudi.github.io/NAGISEN/
  The link opens the web version. The iPhone app is not on the App Store yet, so never write "download on the App Store".
- **Highlights:** black circles with one small word each, like BRUTT: `MOVEMENT` · `KITCHEN` · `NAGISEN` · `FAQ`.
  Covers: post a black story, then pick it as the cover.

## The look

- **Light:** one source only, such as a streetlight, a gym's top light, a window or a phone torch. Everything else falls to black.
- **Motion:** blur is welcome. Use a slow shutter: Live Photo, then swipe up and choose *Long Exposure*. Shooting from a moving body also works.
- **Body:** feet, hands, a back, a shadow or a silhouette. No faces and no logos. Clothes stay black or dark.
- **Colour:** black, grey and burgundy. The script's grade pulls every photo there, so colourful scenes (green turf, a blue sky) still come out on brand.
- **Framing:** portrait, with the subject low or off-centre and a lot of empty dark space.
- **Exposure:** on iPhone, tap the subject and drag the sun icon down until the shadows go black. Underexpose; never brighten.

## Shot list

Files go in `photos/` with these exact names, then run `python3 render.py`.

| File | Shot |
|---|---|
| `01-dumbbells.jpg` | ✓ Dumbbells on the turf, shot from above (already in place) |
| `04-lane.jpg` | Your feet walking the burgundy lane, motion blur (the photo you sent) |
| `05-streetlight.jpg` | A runner crossing one streetlight at night, from behind, Long Exposure |
| `07-breath.jpg` | Hands on knees after a sprint, cold air or sweat, top light |
| `08-stairs.jpg` | Legs climbing stairs, blurred, shot from below |
| `10-rope.jpg` | A jump rope as a blurred arc, the body in shadow |
| `11-shadow.jpg` | Your shadow on a wall mid-movement (a squat or a stride) |

Spares for later: chalked hands on a bar, a swimmer's arm in dark water, sand at Aïn Diab at dusk, a door left open onto the street before dawn.

## The grid (posting order)

Instagram shows the newest post first, so post 01 ends up bottom-right. The rhythm alternates photo, photo, then type.

| # | File | Caption |
|---|---|---|
| 01 | photo, dumbbells | The quiet before the work. |
| 02 | wordmark | NAGISEN. The art of quiet progress. Link in bio. |
| 03 | statement | Progress makes no sound. |
| 04 | photo, lane | Step by step. Even when no one is watching. |
| 05 | photo, streetlight | Before dawn, the city is yours. |
| 06 | statement | No one sees the repetition. It shows later. |
| 07 | photo, breath | Breathe. What counts is the next one. |
| 08 | photo, stairs | One more floor. |
| 09 | wordmark, link in bio | Meals, water, training, habits. One quiet place. NAGISEN, in your browser. Link in bio. |
| 10 | photo, rope | Rhythm comes with time. |
| 11 | photo, shadow | In silence. |
| 12 | statement | Eat. Move. Breathe. Repeat. |

Every caption ends with the same quiet line:

```
— NAGISEN · quiet progress
```

**Hashtags.** Use 3 to 5, in the first comment rather than the caption:
`#nagisen #casablanca #morocco #discipline #fitnessmorocco`.
Rotate in `#rabat #marrakech #bodybuilding #running #nutrition`.

**What the captions may claim.** Only what the app does: tracking meals, water, caffeine and workouts, a daily streak, a coach, and the web version.
Its food search includes 2,146 Moroccan packaged products from Open Food Facts. Never promise results such as weight loss, muscle gained or "in 30 days".

## Stories

Every post has a 1080×1920 version in `out/` (`NN-story.jpg`). The monogram is raised there so the reply bar doesn't cover it.

- **On launch day:** story 02 with the link sticker on *Open NAGISEN*.
- **The next day:** story 03 with a poll sticker: *Do you track what you eat? Yes / Not yet*.
- **For the FAQ highlight:** a black story with this text: *On iPhone: open the link in Safari → Share → Add to Home Screen.*

## Schedule (4 weeks, 3 posts a week)

Post Monday, Wednesday and Friday at 21:00 (Casablanca). Late evening suits the dark mood and is when people scroll.

| Week | Mon | Wed | Fri |
|---|---|---|---|
| 1 | 01 | 02 | 03 + story launch |
| 2 | 04 | 05 | 06 + story poll |
| 3 | 07 | 08 | 09 + link sticker |
| 4 | 10 | 11 | 12 |

Between posts: reshare one story from the post that day, and reply to every comment within the hour.

## Making the files

```bash
cd marketing/instagram
python3 render.py          # renders every post whose photo exists
python3 render.py 04 05    # only these
```

- **Settings per post** live in `posts.json`:
  - `tone`: `wine` (burgundy, the default) or `ash` (neutral grey)
  - `focus`: where to crop, as `[x, y]` from 0 to 1
  - `line`: optional uppercase words over the photo
  - `line_position`: `high`, `center` or `low`
- **Converting iPhone HEIC photos:** `sips -s format jpeg IMG.heic --out photos/NAME.jpg`
- **Not in git:** `photos/` and `out/` stay off GitHub (see `.gitignore`), so your pictures don't go public before you post them. AirDrop the files in `out/` to your phone to post.

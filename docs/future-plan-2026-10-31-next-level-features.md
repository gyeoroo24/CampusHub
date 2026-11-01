# CampusHub — Next-Level Features Plan (Draft)

*As-of 31 Oct 2026 — advisory only, nothing in this document is implemented. Scope: Buy & Sell, Lost & Found, Courses.*

This is a planning document capturing the feature ideas discussed and the user's decisions on each, so a future session can pick an item and scope it properly. No code has been written for anything below.

---

## 1. New Features

### 1.1 In-app buyer-seller messaging (Buy & Sell) — Approved direction, revised

- **Decision**: Keep showing the seller's email/phone to signed-in users (see §3 below — not worth hiding since the whole site is already signed-in-only). **Add** in-app messaging as a genuinely new channel, not a replacement for the contact info.
- **Scope**: threaded chat per listing, optional "make an offer" with accept/reject, so negotiation doesn't have to happen over email.
- **No SLM needed here** — explicitly ruled out for this feature on security grounds (don't want a model inspecting/filtering private messages). Plain text messaging, same auth model as the rest of the app.
- **One chat per person (31 Oct 2026).** Chats are grouped by person, like WhatsApp, not by listing. Each item discussed (a listing, a lost report, a found report) is a *topic* inside that chat: an item card marks where talk about it starts, chips under the header filter to one item, and the composer shows what the next message is about. Offers belong to one listing, and accepting reserves that listing. Messages with no topic are general chat, which is where a future academic-help area would fit without a separate inbox. A "two windows per person" design (chat vs. Buy & Sell / Lost & Found) was considered and rejected: it splits the relationship again and makes people guess where a message went.
- **Status (31 Oct 2026): built, but NOT end-to-end encrypted yet.** Messages are encrypted in the app (X25519 + AES-256-GCM), but the server also stores each user's private key in plain form, so **the server can read the current chats**. Anyone with database access could too. Moderators and admins have no screen for reading chats. This was a deliberate trade-off: the first version locked the key with a messaging passphrase, which made the server unable to read messages but was too much hassle for users (who remembers a passphrase?), so the passphrase was removed.
- **Future work: true end-to-end encryption without a passphrase.** If E2E is needed, the recommended option is **passkey + QR device linking**:
  - **Passkey (main way in).** Use the WebAuthn PRF extension: Face ID / Touch ID / Windows Hello gives the app a secret that encrypts the private key before upload. The server only ever stores the encrypted key. Passkeys sync through iCloud Keychain and Google Password Manager, so a user's other devices unlock with a fingerprint or face, with nothing to remember. Supported by current Chrome, Safari and Edge; Flutter web needs a small JavaScript interop layer.
  - **QR device linking (for devices or browsers without passkey support).** Like WhatsApp Web: a signed-in device shows a QR code, the new device scans it, and the key travels between them encrypted with a one-off key exchange, the server only passing it along.
  - **Recovery key (last resort).** A long generated code the user downloads or prints once.
  - **Moving existing users over:** the app creates the passkey, encrypts the same private key with it and re-uploads it (`PUT /me/chat-key` with the same public key keeps every message readable), then the server deletes the plain copy. Until every user has moved, the server can still read their chats.
  - Alternatives considered: a short PIN guarded by AWS KMS / Nitro Enclaves with a limited number of guesses (WhatsApp's encrypted backups work this way; strong, but the most work); one key per device with no server history (WhatsApp's default; loses history on a new browser).

### 1.2 Lost & Found matching upgrade: photo similarity + description similarity — Built (1 Nov 2026)

Today's matcher is category + time-ordering only. Two upgrades, both approved in principle:

- **Photo similarity**: compare uploaded photos across lost/found reports instead of relying on category alone.
- **Description similarity**: also match on the free-text description field (not just for found reports — explicitly requested to extend this to **lost** reports too), since category alone is coarse (e.g. "Electronics" covers earbuds and laptops equally).

User's condition: *"if there is not much latency introduced... tell me the model name, its size and expected latency first beforehand."* Candidate models and honest latency estimates below (§4) — this needs a sign-off on the specific model before any implementation.

**Status (1 Nov 2026): built** (`backend/app/matching`, migration `012_lf_matching`), after a local benchmark and sign-off:

| Model | Size | Measured (ONNX Runtime, fp32, 1 thread, M-series Mac) |
|---|---|---|
| all-MiniLM-L6-v2 (description vs description) | 90 MB | ~7 ms per description |
| MobileCLIP-S0 image encoder (photo vs photo) | 45 MB | ~36–43 ms per photo |
| MobileCLIP-S0 text encoder (description vs photo) | 170 MB | ~6 ms per description |

The int8 builds were slower on ARM, and the int8 image model lost accuracy, so fp32 is used. Expect 2–3× these times on a 1-vCPU Graviton Lambda.

Decisions taken:
- **Where it runs:** a separate matcher Lambda (`Dockerfile.matcher`), invoked asynchronously by the API, so the API image stays small. Locally it runs in-process.
- **Who gets alerted:** only the owner of a lost report with a **strong** match, in either direction, and across categories.
- **Text↔photo:** added. Lost-report descriptions can match found-report photos, and the reverse.
- **Where matches show:** a ranked "Possible matches" list with Strong/Possible badges and reasons, on the owner's own report and right after filing it.

Without the models the API falls back to the old same-category rule.

**Calibration** (`backend/scripts/calibrate_matching.py`, 20 description pairs, 8 look-alikes, 34 photos of everyday lost items). On descriptions alone, the chosen thresholds alert 14 of 20 true pairs and list the other 6. Of the 8 look-alikes, 1 alerts. None of 364 unrelated pairs alert. Photos add evidence on top. Text↔photo similarity is weak on its own (CLIP scores of 0.1–0.35), so it is capped and only reaches "strong" together with another signal.

### 1.3 Claim-verification step before revealing contact info (Lost & Found) — Deferred

Originally proposed: require answering a reporter-set verifying question before contact info is exchanged on a match, to cut down false claims on valuable items.

- **Decision**: *"Not needed right now."* Parked — revisit only if false-claim abuse becomes an actual problem.

### 1.4 Per-instructor reviews + "My Courses" follow list (Courses) — Deferred

Originally proposed: split course feedback by instructor/offering instead of course-level only, plus a lightweight follow list for notifications on new feedback.

- **Decision**: *"Doesn't feel like we need that right now. Maybe in the future."* Parked, no further scoping done.

### 1.5 Seller trust score, driven by moderator actions (Buy & Sell) — Approved

**Problem**: a seller who repeatedly posts prohibited items (e.g. drugs) gets individual posts flagged and removed by a moderator, but today nothing tracks the *seller* across those removals — each incident is handled in isolation, and a repeat offender looks exactly like a first-time poster with a clean history.

**Decision, as specified by the user**:

- Not a 1–5 star rating — explicitly ruled out, because most sellers only ever sell once or twice during their time at IISc, so a star rating has too little data per seller to mean anything.
- Instead: a seller-level signal driven purely by **moderator-confirmed removals**, not raw report counts (a report alone proves nothing — only a moderator actually removing the content for violating policy should count against the seller). Each time a moderator resolves a report on that seller's listing by removing it, that counts as one strike against the seller.
- Once a seller accumulates multiple strikes, the platform should visibly flag them — e.g. a simple **"Negative Seller"** or **"Blocked Seller"** tag shown wherever their listings appear (feed card + detail dialog), so other students can see it before dealing with them.
- **Normal sellers show no tag at all** — the tag is purely for sellers who've crossed the strike threshold; it is not a neutral/positive badge system, just a warning marker for problem accounts.
- Stated purpose: this isn't about rating sellers for its own sake — it's about **making the moderator's job easier**, by letting the system surface (and optionally auto-suggest blocking) repeat offenders instead of a moderator having to remember or manually cross-reference a seller's history across unrelated reports.

**Implementation sketch (for a future scoping pass, not decided yet)**:

- No model needed — this is pure counting/thresholding logic over data the system already has (the existing `reports` table + the moderator's existing resolve-by-removing action).
- A seller's strike count = number of their listings a moderator has resolved by *removing the content*, not just number of reports received (dismissed reports shouldn't count against the seller).
- Exact thresholds (how many strikes → "Negative Seller" tag, how many → outright blocked from posting) are a moderation-policy decision, not a technical one — left open for whoever scopes this, though §1.5.1/§1.5.2 below give a concrete starting recommendation based on how real platforms handle this.

#### 1.5.1 Research: how real platforms handle this

Searched for real strike/reputation systems that tie repeated moderator-confirmed violations to escalating account consequences. No platform publishes CampusHub's exact scenario (campus P2P marketplace, rare per-user selling activity), but several map closely:

- **YouTube Community Guidelines strikes**: 1st strike = one-time warning (added in 2019 specifically to avoid punishing first-time mistakes), 2nd strike = 2-week upload freeze, 3rd strike within a rolling **90-day window** = channel termination. Critically, **severe violations skip the ladder entirely** and can terminate a channel on the first offense, with no warning. Strikes are visible to the creator and appealable. ([YouTube Help: strike basics](https://support.google.com/youtube/answer/2802032); [Search Engine Journal on the 2019 update](https://www.searchenginejournal.com/youtube-updates-its-strike-system-for-community-guideline-violations/294439))
- **TikTok's 2023 account enforcement system**: same strike-ladder idea, but the **threshold itself varies by how harmful the violation category is** — a stricter (lower) threshold for high-harm policies (e.g. hateful ideologies) than for low-harm ones (e.g. spam), and the worst violations bypass the count and ban on one occurrence. Creators can see their own strikes from the last 90 days and appeal. TikTok's own data motivating this: ~90% of repeat violators kept using the same feature, and 75%+ kept violating the *same* policy category — i.e. strikes are most useful when scoped per violation type, not as one global counter. ([TechCrunch](https://techcrunch.com/2023/02/02/tiktok-introduces-a-strike-system-for-violations-tests-a-feature-to-refresh-the-for-you-feed/); [TikTok Newsroom](https://newsroom.tiktok.com/supporting-creators-with-an-updated-account-enforcement-system?lang=en))
- **Facebook's severity-tiered tolerance**: reportedly allows up to **10** violations of its marketplace gun-sale ban before removal, but only **5** for violence/dangerous-organization content — i.e. the same strike mechanism, but the threshold itself is set per how dangerous the category is. Facebook also confirmed some violations are "one-and-done" regardless of strike count. ([The Hill, citing Washington Post reporting](https://digital-release.thehill.com/?p=3519049))
- **Alibaba's IP strike policy**: 1st–2nd strike = temporary listing restriction + mandatory policy education/exam; **strikes expire if a 3rd isn't reached within 365 days** of the first. This is the clearest real "strike decay" example — it exists because Alibaba's sellers list constantly, so an old, isolated incident years ago shouldn't still count today. ([Conventus Law](https://conventuslaw.com/featured-content/china---demystifying-alibabas-three-strike-policy))
- **eBay's seller standards**: not strike-count based at all — it's a rolling *defect rate* (currently ≤2% of transactions, evaluated monthly), and critically a defect only counts toward the status once it involves **enough distinct buyers** (≥5), specifically so one angry or wrong complaint can't tank a seller. This is the closest real-world validation of a decision already made for §1.5: trigger strikes from *confirmed moderator action*, not raw report volume, for the same anti-gaming reason. ([eBay seller performance standards](https://www.ebay.ie/pages/help/policies/seller-non-performance.html))
- **hobbyDB**: strikes are **not visible to other users** at all — only to the seller and the platform; a seller with strikes simply loses eligibility for a "Trusted Seller" badge. This is the "positive badge withheld" variant, as opposed to a "negative badge shown" variant.

**Pattern across all of them**: (1) a graduated ladder (warning → temporary restriction → permanent), (2) severe-harm categories skip straight to the harshest consequence instead of waiting for repeats, (3) the triggering event is a confirmed moderation action, not a raw complaint, and (4) the account holder can see their own standing and appeal before the harshest step.

#### 1.5.2 Recommended approach for CampusHub

Adapting the pattern above to a small, low-frequency campus marketplace (most sellers post once or twice in years, unlike the high-volume creators/sellers these platforms were designed for):

- **Two severity tiers, not one ladder** (mirrors TikTok/Facebook's severity-scoped thresholds):
  - **Severe tier** (illegal items — drugs, weapons, or anything law-enforcement-relevant): **1 moderator-confirmed removal is enough** to immediately show the "Blocked Seller" tag and suspend their ability to post new listings pending a moderator's manual decision on a full account ban. No warning step — mirrors YouTube's/Facebook's "severe violations skip the ladder" rule, appropriate here because the downside of under-reacting (actual illegal activity on a university platform) is much worse than the downside of a single over-correction, which a moderator reviews anyway.
  - **Non-severe tier** (everything else a moderator removes — prohibited-but-not-dangerous items, scammy/duplicate/misleading listings): a short ladder — **1st removal** = silent record only (no public tag, matches hobbyDB's "not visible to others" step), **2nd removal** = "Negative Seller" tag shown publicly, **3rd removal** = "Blocked Seller" tag + posting suspended pending moderator review.
- **No strike decay/expiry by default** — unlike YouTube's 90-day or Alibaba's 365-day windows, those exist because those sellers post constantly; a CampusHub seller who gets 2 confirmed removals across their *entire* multi-year stay is still a meaningfully bad signal, so there's no natural "stale incident" to forgive the way there is on a high-volume platform. Worth revisiting only if real usage shows otherwise.
- **Trigger stays moderator-action-only, not report-count**, consistent with eBay's "needs multiple distinct buyers" anti-gaming logic — a strike only happens when a moderator actually removes the listing for a policy violation, never from reports alone.
- **Give the seller visibility + a lightweight appeal before anything public happens**, matching YouTube/TikTok: notify the seller when a strike lands, and let them contest it to a moderator before it counts toward the public tag (not before the private record — the record itself should be immediate and tamper-proof).
- Exact numeric thresholds above (1/2/3) are a starting proposal, not final — intentionally kept simple since this is still an advisory plan, not an implementation.

**Status (1 Nov 2026): built**, running locally against the real backend — `backend/app/seller_trust.py` (tag/threshold/hide logic), `backend/db/migrations/013_seller_trust.sql` + `014_reversible_listing_hide.sql` (schema), wired into `backend/app/routers/reports.py` (strike trigger), `backend/app/routers/listings.py` (tag display, hidden-listing visibility gating, posting suspension) and `backend/app/routers/seller_trust.py` (seller/moderator endpoints). Thresholds are `Settings.seller_strike_*` (`backend/app/config.py`), still the 1/severe, 2/negative, 3/blocked starting proposal from §1.5.2 above:

- **Trigger**: only `POST /reports/{id}/resolve` with `remove_content=true` on a `listing` creates a strike — never the direct `DELETE /listings/{id}` a moderator or the seller themself can also call, and never a raw report. Resolving now requires a `severity` ('severe'/'non_severe') on a listing removal, enforced with a 422 if missing — a moderator-facing severity picker was added to the Reports Queue dialog (`frontend/lib/features/admin/ui/admin_controls_screen.dart`) for exactly this.
- **Removal is reversible, not a delete — revised after first-pass feedback.** The first build soft-deleted the listing the same way any other moderation removal does (`deleted_at`), and only made the *strike* reversible (overturning it un-counted the strike but never brought the listing back). That was wrong: a report-driven removal now sets `listings.hidden_by_strike_id` instead of `deleted_at`. A hidden listing is invisible to everyone except its seller and a Buy & Sell moderator/admin (`GET /listings` and `GET /listings/{id}` check the real signed-in viewer, not just a query filter, so nobody can peek via `?seller_id=`) — and overturning the strike that hid it makes it visible to everyone again, exactly as asked. The pre-existing, unrelated `DELETE /listings/{id}` path (a seller removing their own listing, or a moderator acting outside the report flow) is untouched and stays a permanent soft-delete.
- **Tag + suspension**: `seller_trust_tags()` computes 'negative'/'blocked' per seller from non-overturned strikes and is shown via `seller_trust_tag` on `ListingSummary`/`ListingDetail`, rendered by a shared `SellerTrustBadge` widget on the Buy & Sell grid card, list card and detail dialog (nothing for normal sellers — confirmed in the browser: 2 non-severe strikes → "Negative Seller" on every listing by that seller; 1 severe strike → "Blocked Seller" + `POST /listings` returns 403 for that seller). A moderator or admin can also lift a suspension directly (`POST /users/{id}/lift-listing-suspension`) without overturning the strike that caused it.
- **Appeal, now with an explicit moderator decision either way.** A strike counts immediately (tamper-proof, never deleted) and the seller is notified in-app (`moderation_action` notification) right away. The seller can file one written appeal per strike (`POST /me/seller-strikes/{id}/appeal`) from the new "Seller strikes" screen (account menu → Seller strikes, `frontend/lib/features/seller_trust/`). A Buy & Sell moderator or admin then either **overturns** it (`POST /seller-strikes/{id}/overturn`: excludes the strike from the count, restores the listing, auto-lifts a suspension it caused) or **rejects the appeal** (`POST /seller-strikes/{id}/reject-appeal`: the strike stands and the listing stays hidden, but it drops out of the "needs review" queue). This is still simpler than gating public visibility behind an open appeal window the way §1.5.2's literal wording suggests — a strike is visible/counted from the moment it's recorded, not after a grace period — a deliberate trim, not an oversight.
- **Moderator queue**: a new "Seller Strikes" tab in the admin/moderator panel (visible to admins and Buy & Sell moderators, next to "Reports Queue"), backed by `GET /seller-strikes?appeal_status=pending|resolved|none|all&seller_id=...`. It defaults to `pending` — strikes a seller has contested that nobody has reviewed yet — exactly the "moderator's view shows this listing is contested" the feedback asked for, with the seller's name, the listing (clickable through to its detail dialog even while hidden), the moderator's own original note, and the seller's appeal text all in one card.
- **Verified locally** (curl + full browser walkthrough, both roles signed in): a report resolved with `remove_content` hides the listing (owner and moderator still see it, `hidden: true`; a third party gets 404, and it's gone from the public feed and from an outsider's `seller_id`-filtered search); the seller opens "Seller strikes," sees the hidden item and files an appeal; the moderator's "Seller Strikes" tab immediately shows it under PENDING with the seller's exact appeal text; clicking **Overturn** restores the listing (`hidden: false`, visible to everyone again) and clears the queue; a separate test confirmed **Reject appeal** instead keeps the listing hidden and moves the strike to the RESOLVED filter. Permission and double-submit guards also verified: a non-moderator gets 403 on overturn/reject, a non-owner gets 409 appealing someone else's strike, and rejecting an appeal that's already resolved gets 404.

### 1.6 Automatic (proactive) flagging of illegal, spammy, or gibberish/obscene posts — Built (2 Nov 2026)

**Problem, as specified by the user**: today, a bad post only reaches the moderator if another student notices it and files a report (§1.1's reporting feature, already built). That's reactive and relies on someone else doing the work. The user wants a *proactive* layer: the system itself should detect clearly-bad posts and push them into the moderator queue automatically, without waiting for a human to report them — explicitly called out cases: **(a)** someone selling something illegal (e.g. drugs), **(b)** someone spamming Buy & Sell / Lost & Found with repeated, not-really-relevant listings, **(c)** a listing with a gibberish title, **(d)** a listing with an obscene image.

**Decision**: build this as a pipeline that runs automatically on every new listing/lost-found post and, if it trips any of the checks below, **auto-creates a report in the exact same moderator queue** that `createReport()` (§1.1, already shipped) feeds — so moderators see system-flagged and student-flagged reports in one place, no separate UI needed. This also plugs directly into §1.5's seller trust score: if a moderator confirms and removes a system-flagged post, it counts as a strike exactly like a user-reported one.

**The four checks, and what real marketplaces do for each**:

- **(a) Illegal/prohibited item in the title or description** — real precedent: **Mercari** (a P2P marketplace, closest real-world analogue to CampusHub's Buy & Sell) explicitly runs ML models trained on past violations to catch categories "prohibited by law," including weapons and counterfeit goods, rather than waiting for buyer reports. ([Mercari AI — Auto Content Moderation for Trust & Safety](https://ai.mercari.com/en/projects/auto-content-moderation-for-trust-safety)) A 2024 marketplace-moderation patent describes the general pattern: score listing text/images against policy categories, and anything above a confidence threshold gets pulled into pre-moderation instead of waiting on a report. ([USPTO — pre-moderation of non-compliant listings](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10937033))
- **(b) Spam / repeated low-relevance listings from the same user** — this doesn't need a model at all: it's a rate/duplicate check (e.g. the same user posting many near-identical titles within a short window). A moderation-pipeline guide recommends exactly this as a cheap first-pass check before anything ML-based runs. ([Vettly — marketplace moderation pipeline](https://vettly.pages.dev/blog/marketplace-moderation-pipeline))
- **(c) Gibberish title** — also doesn't need a model for a first pass: a simple heuristic (ratio of real dictionary words, repeated-character runs, a language-detection confidence score) catches the obvious cases cheaply. Only worth a model if the heuristic proves too weak in practice.
- **(d) Obscene image** — this is the one check that genuinely needs a vision model (an NSFW/obscenity image classifier), since there's no text to pattern-match against. See §4.5 for specific small-model options.

**Routing recommendation, based on the research above**: not every flagged post should be treated the same way.
- For the **illegal-item check specifically**, auto-hide the listing immediately (pending moderator confirmation) rather than just flagging it — mirrors the "pending state until checks pass" pattern from the Vettly pipeline guide, and is the same reasoning used for §1.5's severe-tier strikes: the cost of a false positive (a listing hidden for a few hours until a moderator clears it) is much lower than the cost of a real illegal listing staying visible.
- For spam, gibberish, and obscene-image checks, auto-flag into the moderator queue but **leave the post visible** until a moderator actually acts — these are lower-stakes categories where an eager false positive would annoy a legitimate seller for no good reason.
- Every real source surveyed agrees automated screening should stay paired with a human decision, not replace it — none of these checks should auto-delete anything outright; they only get a post in front of a moderator faster than waiting for a report. ([Foiwe — AI content moderation for marketplaces](https://www.foiwe.com/?p=30916))

**Status (2 Nov 2026): built.** Code: `backend/app/screening.py` (text checks), `backend/app/matching/photo_screen.py` and `nsfw.py` (photos), migration `015`.

- **Prohibited items (listings).** These are held, meaning hidden from everyone but the seller and moderators, until a moderator decides.
  - **Text similarity:** the listing is compared with bge-small-en-v1.5, which the API already ships for category suggestion and which is stronger than MiniLM on short titles. It is compared against 16 prohibited-item descriptions, *and* against harmless look-alikes (water bottles, toy guns, kitchen knives, beer mugs, previous-year papers). It flags when the closest prohibited description scores ≥ 0.60 and beats the closest harmless one.
  - **Keyword list:** a short list of unambiguous words (ganja, MDMA, vodka, pistol, …) flags on its own.
  - **Calibration:** on 19 illegal titles and ~150 ordinary ones, similarity alone caught 15/19 and the word list caught the rest. No ordinary title was flagged, including "BB gun toy", "beer mug" and "kitchen knife set".
- **Gibberish (title or description).** These rules need no model:
  - keyboard runs such as asdf;
  - the same letter three times;
  - five consonants in a row;
  - mostly non-words, judged against the 21,700 whole words in the bge tokenizer's vocabulary. Brands and names that can be pronounced pass.
- **Spam.** The third near-identical post from the same person within 24 hours, or more than 8 posts in an hour.
- **Obscene photos.** Uses Falconsai/nsfw_image_detection (ViT, Apache-2.0), the int8 ONNX build at 87 MB, which takes about 55 ms per photo. It runs after the response, in the matcher Lambda (or a background task locally). On 46 ordinary photos the highest score was 0.004, against a flag threshold of 0.8. It could not be tested on real obscene images, so its catch rate rests on the published accuracy.
- **Routing.** Every flag is a report with `source = 'system'` (no reporter), shown with an AUTO label in the moderator queue. There is one open automatic report per item; a later check appends its reason.
  - The owner is told when their post is flagged or held.
  - A moderator's decision releases a hold. A confirmed removal of a listing is a seller-trust strike, as with any report.
  - `CAMPUSHUB_AUTO_FLAG=false` turns flagging off.

---

## 2. Improvements to Existing Features

### 2.1 Replace the lexicon sentiment scorer with a small ML model — Approved, analysis below

`app/sentiment.py` is currently a hand-built, VADER-style word-list scorer (no model, no API calls). User agreed this should move to an actual small model, and specifically asked for a comparison against alternatives at a similar parameter size/speed, not just "swap in DistilBERT." See §4.1 for the comparison and recommendation.

### 2.2 Lost & Found fuzzy description matching — Approved

Folded into §1.2 above — same embedding-based approach covers both the "new feature" (photo+description matching) and this "improvement" (moving off category-only matching).

### 2.3 Buy & Sell: price-drop watch, with a "negotiable" signal — Built (2 Nov 2026)

Originally proposed as two separate things (a 1–5 star course rating, and a watch-this-listing price-drop alert). Decision:

- **Course star rating**: *"No need to add rating of 1-5 for course feedback right now. It can be in more future."* Parked.
- **Price-drop watch**: keep this one. Additional requirement added: since buyers and sellers will often just negotiate instead of the seller formally dropping the listed price, the listing should support marking a price as **"Negotiable"** (a simple boolean/badge on the listing), separate from the watch/alert mechanism itself. A watcher should plausibly be notified either when the listed price actually changes, or when a listing they're watching gets marked negotiable.

**Status (2 Nov 2026): built.**
- **Negotiable:** listings have a `negotiable` flag, set by a checkbox when posting or editing. It shows as a "Negotiable" badge on cards and the listing.
- **Watching:** "Watch price" on someone else's listing (`PUT`/`DELETE /listings/{id}/watch`). The account menu has "Watched listings" (`GET /me/watched-listings`).
- **Who is notified:** watchers get a `listing_watch` notification when the price changes ("Price drop on "Hero Sprint": ₹4,000 → ₹3,200") or when the listing is marked negotiable. The seller is never notified, and nothing is sent once the listing is sold or hidden.

### 2.4 Auto-suggest category from listing title — Built (1 Nov 2026)

Decision: *"Based on the title, we can auto suggest a category... fine with me."* But with an important constraint: **it must not suggest a different new category every time** for similar titles — it should first check whether an **existing** category matches well, and only fall back to suggesting something else if nothing existing fits well.

- Practical implication for the design: this should be implemented as **nearest-neighbor matching against the existing category set** (and ideally against existing listings/titles already tagged with each category), not as a generative/free-form classifier that can hallucinate a new label each time. This is naturally stable: the same title (or a near-duplicate) will always map to the same closest existing category, because it's doing a similarity lookup against a fixed, small label set rather than generating an answer from scratch. See §4.3 — this reuses the same text-embedding model as §1.2/§2.2, no separate model needed.

**Status (1 Nov 2026): built** (`backend/app/categories_suggest.py`, `GET /buy-sell/categories/suggest` and `GET /lost-found/categories/suggest`). The Buy & Sell "Post Listing" dialog shows a "Suggested category" chip 500 ms after typing stops; the suggestion is never applied automatically.

**Revised the same day.** The first version reused MiniLM on bare category names with a 0.2 threshold. It suggested "Bottle" for "plant" whenever no Plant category existed, because one-word labels sit close together in embedding space and 0.2 lets almost anything through. It was rebuilt after measuring the options on 87 labelled titles (`backend/scripts/calibrate_category_suggest.py`). The set includes titles that fit no category, and a run with two categories removed.

| Approach | Top pick right | At its safest setting | Speed | Size |
|---|---|---|---|---|
| MiniLM, bare names (first version) | 56/79 | 23 right, 55 silent | 8 ms | 90 MB |
| gte-small / arctic-embed-xs / MiniLM-L12 + listings | 63–69/79 | 50–53 right | 2–21 ms | 90–133 MB |
| NLI re-ranker (xtremedistil zero-shot) | 61/79 | worse than without it | +3 ms | 13 MB |
| **Qwen2.5-0.5B-Instruct names a category** (the "LLM + map to nearest" idea) | — | 47 right but **24 wrong**; "asdfgh" → Books | **~260 ms** | 833 MB |
| **bge-small-en-v1.5 int8 + phrase + recent listings + margin (chosen)** | **71/79** | **55 right, 2 wrong**, silent on all 8 no-fit titles | **~3 ms** | **34 MB** |

How the chosen approach scores a title:
- **Category phrase:** the title is compared with "a <name> item for sale", not the bare name.
- **Recent listings:** it is also compared with the closest of that category's 20 most recent listings (or Lost & Found reports), at 30% weight. This adapts as listings accumulate, with no retraining.
- **Bar to suggest:** the best score must be at least 0.52 and lead the runner-up by 0.03 or more (`category_suggest_threshold` / `_margin`). Otherwise there is no suggestion.

It runs in the API itself. Both API images fetch the model with `scripts/fetch_match_models.py --suggest-only`. The first request in a container takes about 0.35 s to load the model and embed recent listings; later requests take about 6 ms. Without the model, the endpoint returns `{"category": null}`.

---

## 3. Explicitly ruled out / not changing

- **Hiding email/phone from other signed-in users**: *"This is not needed right now. Since only the signed-in users can access this site right now so it's fine even if they see each other's email addresses (or phone numbers if added to their profile)."* No change — contact info stays visible to signed-in users, as it is today. Messaging (§1.1) is purely additive.

---

## 4. Small-model (SLM) analysis

Five distinct pieces of "intelligence" are in scope across the approved items: (a) text-embedding similarity for Lost & Found description matching, category suggestion, and a first-pass illegal-item text check, (b) image-embedding similarity for Lost & Found photo matching, (c) sentiment classification for course feedback, and (d) obscene-image classification for automatic flagging. The question of whether one model can cover all of them is answered in §4.5.

### 4.1 Course sentiment model — comparison at similar size/speed

| Model | Params | Type | Notes |
|---|---|---|---|
| **Current**: hand-built lexicon scorer | 0 (no model) | Rule-based | Baseline being replaced. Brittle on negation, sarcasm, short/mixed reviews. |
| `distilbert-base-uncased-finetuned-sst-2-english` | ~66M | Distilled BERT, binary sentiment | The "obvious" choice. ~91% accuracy on SST-2 (a movie-review benchmark, not course reviews). |
| **`microsoft/deberta-v3-xsmall`** (fine-tuned for sentiment) | ~70M total (22M backbone + embeddings) | DeBERTa-v3, disentangled attention + ELECTRA-style pretraining | **Recommended alternative.** Same size class as DistilBERT but a newer architecture that consistently outperforms BERT/RoBERTa-style models at matched parameter counts on GLUE-style tasks, because disentangled attention gives it more effective capacity per parameter. Would need fine-tuning on review-style text (course reviews skew differently from movie reviews) rather than being used off-the-shelf. |
| `cardiffnlp/twitter-roberta-base-sentiment-latest` | ~125M | RoBERTa-base, trained on informal/social text | Secondary option if we're willing to go ~2x the size: trained on casual, informal text (closer to how students actually write reviews) and 3-way (positive/neutral/negative) rather than binary, which maps better onto the existing "positive/negative/mixed" labeling than a binary SST-2 model does. |

**Recommendation**: `deberta-v3-xsmall` fine-tuned on a small labeled set of course-review-style text, as a same-size, better-architecture swap for DistilBERT. If fine-tuning data is a blocker, `cardiffnlp/twitter-roberta-base-sentiment-latest` is the pragmatic fallback — bigger, but already trained on informal text and already 3-way, so it could be used closer to off-the-shelf.

**Latency (CPU, single review, rough order of magnitude)**: all three are small enough that a single-sentence inference is on the order of **tens of milliseconds on CPU** (roughly 15–60ms depending on hardware and sequence length), i.e. imperceptible for a feature that runs once per submitted review (or batched overnight for the survival-guide aggregation), not per page load. These are vendor/community-reported figures, not benchmarked on our own hardware — worth a quick local benchmark before committing.

### 4.2 Lost & Found — text + image similarity

| Model | Params | Size | Modality | Est. CPU latency (single item) |
|---|---|---|---|---|
| **`all-MiniLM-L6-v2`** | 22M | ~90MB (unquantized) | Text embedding (384-dim) | ~14ms per sentence on CPU (general-purpose build); as low as ~2ms with a hardware-accelerated runtime (e.g. Core ML on Apple Silicon). Thousands of sentences/sec throughput reported on CPU. |
| `e5-small-v2` / `bge-small-en-v1.5` | ~33M | ~130MB | Text embedding | Slightly larger/slower than MiniLM, modestly better retrieval quality; requires specific query/passage prefixes which complicates a drop-in swap. |
| **`MobileCLIP-S0`** (Apple) | ~11–12M (image encoder) | Tens of MB | Image embedding | Purpose-built for on-device/mobile inference; expected single-digit-to-low-tens-of-ms on CPU, faster still with a mobile NPU/Core ML. |

**Recommendation**: `all-MiniLM-L6-v2` for description-similarity matching (covers both lost and found reports, per the user's request), and `MobileCLIP-S0` (or an equivalent small CLIP-style distilled model) for photo-similarity matching. Both are embedding models — matching is just a cosine-similarity lookup against recent open reports, no training needed, and both are well under the latency budget for a background/async matching job (this doesn't need to run synchronously on page load — it can run the same way the existing rule-based matcher runs today, i.e. on report creation).

Caveat: these are vendor/community-reported numbers, not measured on CampusHub's own infrastructure. Before building, worth a 30-minute local benchmark (run both models on ~20 real report photos/descriptions on the actual deployment hardware) to confirm the latency holds up, per the user's condition that this only proceeds if latency stays low.

### 4.3 Category auto-suggestion — no new model needed — Built (1 Nov 2026)

Reuses `all-MiniLM-L6-v2` from §4.2: embed the typed title, compare against embeddings of existing category labels (and/or existing listing titles already tagged per category), and suggest the nearest existing category above a similarity threshold. Only if nothing clears the threshold would it fall back to no-suggestion (never to inventing a new category name) — this directly satisfies the "don't suggest a different new category every time" requirement, since nearest-neighbor lookup against a fixed label set is deterministic for a given title, unlike a generative classifier.

**Superseded (1 Nov 2026):** MiniLM on bare labels proved too weak for one-word category names. Category suggestion now uses bge-small-en-v1.5 (int8, 34 MB) with category phrases, recent listings and a margin rule; see §2.4 for the measurements.

### 4.4 Automatic flagging (§1.6) — models for the two checks that need one

Of the four checks in §1.6, two (spam-by-repetition, gibberish titles) are plain heuristics with no model. The other two:

- **Illegal-item text detection**: rather than a 5th model, this can **reuse `all-MiniLM-L6-v2` a third time** (already used for §1.2/§2.2 description matching and §2.4 category suggestion) — embed the listing's title+description, compare similarity against a small curated set of known-prohibited-item example phrases, and flag anything above a similarity threshold. Same "nearest-neighbor against a fixed set" pattern as category suggestion (§4.3), just with a "prohibited" exemplar set instead of a "category" one. If this proves too coarse in practice (a real classifier would separate "illegal" from "merely similar-sounding" better than pure similarity), the fallback is a small fine-tuned text classifier at the same size class as §4.1's sentiment model (~22–70M params) — Mercari's own real system (§1.6) uses trained classifiers, not similarity search, for exactly this reason.
- **Obscene image detection**: a genuinely new, 4th model is needed here — no existing text or embedding model can classify images for obscenity. Candidate: **`Falconsai/nsfw_image_detection`** (ViT-based, Apache 2.0, binary NSFW/safe), quantized to ONNX — reported sizes range from ~343MB at full precision down to **~87MB at INT8**, with **~270ms per image on CPU** after a ~370ms one-time model load. That's too slow to run synchronously on upload for a snappy UX, but it doesn't need to be synchronous — per the Vettly pipeline pattern in §1.6, this can run as an async post-upload check (same pattern already used for the existing photo-upload flow), so 270ms is irrelevant to perceived latency. A smaller (~1MB, ~65ms) WASM-based classifier exists but was built and tuned for pixel art, not general photos, so it's not a reliable substitute without separate validation. ([nsfwpy-onnx package](https://pypi.org/project/nsfwpy-onnx/); [DEV Community — 1MB WASM NSFW classifier](https://dev.to/matias_affolter/how-i-built-a-nsfwjs-alternative-thats-25x-lighter-1-mb-gzipped-and-runs-in-65-ms-wasm-23o3))

### 4.5 Can one SLM cover everything, or do we need several?

**Answer: the reused text-embedding model covers three of the five intelligent pieces now in scope; two more small models are needed — one classifier, one vision model.**

- **One text-embedding model does triple duty**: `all-MiniLM-L6-v2` (or similar) now powers Lost & Found description matching (§1.2/§2.2), category auto-suggestion (§2.4), *and* a first-pass illegal-item text check (§4.4/§1.6), because all three are the same underlying operation — "find the nearest existing thing in embedding space" — just applied to different example sets (descriptions, category labels, prohibited-item phrases). No separate model needs training for any of the three.
- **Sentiment needs its own model**: a general embedding model is tuned for semantic *similarity*, not sentiment *polarity* — two reviews can be semantically similar (both about "exam difficulty") while having opposite sentiment. This needs a dedicated classifier head, hence a separate small model (§4.1) — which, if the embedding-similarity approach to illegal-item detection proves too coarse, doubles as the architecture template for a dedicated illegal-item classifier too (same size class, different fine-tuning data).
- **Image tasks need their own models, and photo-matching ≠ obscenity detection**: embedding models for text and images are different architectures trained on different modalities, so a text model can't be reused for either image task. Worse, photo-*similarity* (§1.2/§4.2, "do these two photos show the same object") and photo-*obscenity classification* (§1.6/§4.4, "is this photo inappropriate") are two different vision tasks even though both are "about images" — MobileCLIP's embeddings aren't trained to separate obscene from non-obscene content, so this needs its own dedicated model (`Falconsai/nsfw_image_detection` or similar).

So the realistic footprint is now **4 small models total** (one text-embedding model reused across three features, one sentiment classifier, one image-similarity embedding model, one image-obscenity classifier) — not a single do-everything SLM, and not five separate models either, since the text-embedding reuse still collapses three features into one model. All four are small enough (11M–90MB each) to run locally/self-hosted with no per-request API cost, consistent with the "small model, low latency" constraint.

---

## 5. Summary table

| Item | Status | Notes |
|---|---|---|
| In-app messaging (Buy & Sell) | Built (31 Oct); E2E pending | Server can read chats for now; E2E via passkey + QR linking, §1.1. No SLM — security decision |
| Keep email/phone visible to signed-in users | Approved (no change) | Already the behavior today |
| Lost & Found photo matching | Built (1 Nov) | MobileCLIP-S0 image + text (text↔photo), separate matcher Lambda, §1.2 |
| Lost & Found description matching (lost **and** found) | Built (1 Nov) | all-MiniLM-L6-v2, any category; alerts only strong matches, §1.2 |
| Claim-verification step | Deferred | Revisit if abuse becomes a problem |
| Per-instructor reviews / follow list | Deferred | "Maybe in the future" |
| Seller trust score / "Negative Seller" tag | Built (1 Nov) | No SLM — moderator-removal counter + posting suspension; removal reversibly hides the listing, with a seller appeal screen and a moderator contested-queue tab, §1.5 |
| Sentiment model (replace lexicon) | Approved | deberta-v3-xsmall recommended, §4.1 |
| Price-drop watch | Built (2 Nov) | Watch price + "Negotiable" badge, §2.3 |
| Course 1–5 star rating | Deferred | "More future" |
| Category auto-suggest from title | Built (1 Nov) | bge-small-en-v1.5 int8 (34 MB) in the API; Buy & Sell form only so far, §2.4 |
| Automatic flagging (illegal items, spam, gibberish, obscene images) | Built (2 Nov) | bge-small + harmless anchors + word list; heuristics; NSFW ViT int8 in the matcher Lambda, §1.6 |
| Single SLM vs. multiple | Analyzed | 4 small models total, one reused across 3 features — §4.5 |

---

## Sources consulted for model comparison

- [DistilBERT base uncased finetuned SST-2 English](https://www.promptlayer.com/models/distilbert-base-uncased-finetuned-sst-2-english)
- [all-MiniLM-L6-v2 — ExecuTorch latency benchmarks](https://huggingface.co/mlboydaisuke/all-MiniLM-L6-v2-ExecuTorch)
- [What is all-MiniLM-L6-v2 — Superlinked glossary](https://superlinked.com/glossary/what-is-all-minilm-l6-v2)
- [Popular pretrained sentence transformer models compared — Zilliz](https://zilliz.com/ai-faq/what-are-some-popular-pretrained-sentence-transformer-models-and-how-do-they-differ-for-example-allminilml6v2-vs-allmpnetbasev2)

## Sources consulted for automatic flagging (§1.6)

- [Mercari AI — Auto Content Moderation for Trust & Safety](https://ai.mercari.com/en/projects/auto-content-moderation-for-trust-safety)
- [USPTO — pre-moderation service for non-compliant listings](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10937033)
- [Vettly — marketplace moderation pipeline](https://vettly.pages.dev/blog/marketplace-moderation-pipeline)
- [Foiwe — AI content moderation for marketplaces & e-commerce](https://www.foiwe.com/?p=30916)
- [nsfwpy-onnx (quantized Falconsai NSFW model) — PyPI](https://pypi.org/project/nsfwpy-onnx/)
- [DEV Community — 1MB WASM NSFW classifier](https://dev.to/matias_affolter/how-i-built-a-nsfwjs-alternative-thats-25x-lighter-1-mb-gzipped-and-runs-in-65-ms-wasm-23o3)

## Sources consulted for the seller trust score (§1.5)

- [YouTube Help — Community Guidelines strike basics](https://support.google.com/youtube/answer/2802032)
- [Search Engine Journal — YouTube's strike system update](https://www.searchenginejournal.com/youtube-updates-its-strike-system-for-community-guideline-violations/294439)
- [TechCrunch — TikTok's 2023 account enforcement/strike system](https://techcrunch.com/2023/02/02/tiktok-introduces-a-strike-system-for-violations-tests-a-feature-to-refresh-the-for-you-feed/)
- [TikTok Newsroom — updated account enforcement system](https://newsroom.tiktok.com/supporting-creators-with-an-updated-account-enforcement-system?lang=en)
- [The Hill — Facebook's gun-sale strike tolerance, citing Washington Post](https://digital-release.thehill.com/?p=3519049)
- [Conventus Law — Alibaba's three-strike IP policy](https://conventuslaw.com/featured-content/china---demystifying-alibabas-three-strike-policy)
- [eBay — seller performance / non-performance standards](https://www.ebay.ie/pages/help/policies/seller-non-performance.html)

*Figures above are vendor/community-reported, not benchmarked on CampusHub's own hardware — treat as directional until locally verified.*

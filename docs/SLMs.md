# SLMs: self-hosted models vs. AWS-managed alternatives

*As of 7 Nov 2026 — all five models below are built, calibrated and running.*

CampusHub runs five small models (SLMs) of its own, plus two features that turned out to need no
model at all. For each model this doc records: what it does, why it's self-hosted rather than
called through an AWS-managed API, what that managed alternative would have cost in accuracy and
money, and the one place (course-feedback sentiment) where both paths were actually built, as a
runtime toggle. This is the as-built record of that decision, not a proposal — it's kept mainly so
a later change (more traffic, a commercial deployment, a different licence constraint) has the
original reasoning to revisit rather than relitigate from scratch. The AWS stack it's built on is
the one the [PRD](CampusHub-PRD-v1.pdf) committed to (Lambda, API Gateway, RDS, S3, Cognito,
ap-south-1/Mumbai).

---

## 1. What's built

| # | Model | Params / size | Task | Where it runs |
|---|---|---|---|---|
| 1 | `all-MiniLM-L6-v2` | 22M / ~90MB | Lost & Found: description-vs-description similarity matching | Matcher Lambda / inline matching only (`CAMPUSHUB_MATCH_MODE`) — not shipped with the always-on API |
| 2 | `MobileCLIP-S0` | ~11–12M image encoder + text encoder / tens of MB | Lost & Found: photo-vs-photo and text-vs-photo similarity matching | Matcher Lambda / inline matching only, alongside MiniLM |
| 3 | `bge-small-en-v1.5` (int8) | 33M / 34MB | Buy & Sell / Lost & Found category auto-suggestion from a title, **and** the prohibited-item text check in automatic flagging (same loaded model, reused — see below) | The main API image (ML layer), always loaded |
| 4 | `cardiffnlp/twitter-roberta-base-sentiment-latest` (int8) | RoBERTa-base / ~126MB | Course-feedback sentiment for the survival guide | The main API image; swappable at runtime for Amazon Comprehend, see §1.1 |
| 5 | `Falconsai/nsfw_image_detection` (int8) | ViT-base / 87MB | Obscene-photo check in automatic flagging | Matcher Lambda only (needs the image model) |

Two more pieces of the same "could this need a model" question turned out not to need one:

| Feature | What it does | Why no model |
|---|---|---|
| Placement compensation parsing (`app/placement_roles.py`) | Reads pay from free text in uploaded sheets ("₹ 12,00,000", "15.05 lakhs.", "12-15 LPA", "2021600 rupees per Annum", list numbers, other currencies) | A handful of deterministic rules (units, ranges, per-month, Indian digit grouping) read 566/566 and 336/445 amounts on the two real files tried; every miss is a cell with no amount in it at all. A model would add size and nondeterminism for zero measured gain; the original text is always kept beside the parsed number. |
| Mess-menu reading (`app/mess_extract.py`) | Prefills a mess menu form from a scanned PDF or photo | **Tesseract 5** (LSTM English model, ~4 MB, Apache-2.0) reads each table cell directly — no embedding or classification step. pypdfium2 renders the page, numpy finds the ruled lines, Tesseract's own orientation check (`--psm 0`) uprights sideways pages, and a small slant is corrected by finding the angle where rows line up best. On the five sample menus (A–E) it reads all 28 meals; a few words per page come out misspelt ("Matta nce"), which is why a moderator always reviews the table before posting — nothing is posted automatically. RapidOCR (PaddleOCR's ONNX det/rec models, ~15 MB) was tried first and ran words together on this menu's coloured text ("ChapatiMattaceRamei"); Tesseract won on accuracy. |

### 1.1 Course-feedback sentiment: both paths actually exist

Sentiment is the one feature where self-hosted and AWS-managed were both built, as one setting:

| `CAMPUSHUB_SENTIMENT_BACKEND` | What scores the sentences |
| --- | --- |
| `auto` (default) | the local RoBERTa model when its files are in the image, else the word list |
| `local` | the RoBERTa model, in the API process (~5 ms a sentence on one core) |
| `comprehend` | Amazon Comprehend `BatchDetectSentiment` (25 sentences a call), score = Positive − Negative; needs `comprehend:BatchDetectSentiment` on the API role and `CAMPUSHUB_COMPREHEND_REGION` (default ap-south-1) |
| `lexicon` | the original VADER-style word list (`app/sentiment.py`) |

`app/sentiment_backends.py` picks the backend from that one setting, with no code change between
local and AWS. Whatever the backend, a failure falls back to the word list for that request, so
the survival guide never breaks. The model scores a sentence as P(positive) − P(negative), so
neutral facts ("Assignments are due every Friday") land near 0 and "Great content, but the
grading was opaque" comes out mildly positive, which the word list alone got wrong. Themes and
advice detection stay rule-based either way. Tests: `tests/test_sentiment_backends.py`.

### 1.2 Category suggestion and the prohibited-item check share one model

Category auto-suggestion (`app/categories_suggest.py`) first reused MiniLM on bare category
names with a 0.2 threshold, and made bad suggestions (e.g. "plant" → "Bottle" when there was no
Plant category). It now runs its own model, **bge-small-en-v1.5**, scoring each category as a
phrase ("a `<name>` item for sale") blended with its recent listings; a suggestion needs a
calibrated score (0.52) and a clear lead (0.03) over the runner-up
(`scripts/calibrate_category_suggest.py`). Because this model is already loaded for every request
to the main API, automatic flagging's prohibited-item check (`app/screening.py`) reuses the same
instance instead of loading a second model: it compares a listing's title and description against
short descriptions of what can't be sold on campus (drugs, alcohol, tobacco, weapons, fake
documents, leaked papers, counterfeits, stolen goods, fireworks, "I'll write your exam") and
against harmless look-alikes (water bottles, toy guns, kitchen knives, beer mugs), flagging when
the best prohibited match is close and beats the best harmless one. A short list of unambiguous
words (ganja, MDMA, vodka, pistol...) flags on its own. Calibrated 2 Nov 2026 on 19 illegal and
~150 ordinary titles: 15/19 caught by similarity alone, the rest by the word list; no ordinary
title flagged (full numbers: `docs/auto-flag-accuracy.md`). A prohibited-item flag also **holds**
the listing (hidden from everyone but the seller and moderators) until a moderator decides — a few
hours of a legitimate listing being hidden costs much less than an illegal one staying up. Nothing
is ever auto-removed; a moderator always decides, same as every other automatic flag.

---

## 2. AWS-native alternative for each, and what was decided

| # | Self-hosted model | AWS-managed alternative | Decision |
|---|---|---|---|
| 1 | `all-MiniLM-L6-v2` | Amazon Bedrock — Titan Text Embeddings V2 | **Kept self-hosted.** Already calibrated against real CampusHub data; see §4.1. |
| 2 | `MobileCLIP-S0` | Amazon Bedrock — Titan Multimodal Embeddings G1 | **Kept self-hosted.** Already calibrated; Titan Multimodal has no published accuracy figure to compare against; see §4.2. |
| 3 | `bge-small-en-v1.5` | Amazon Bedrock — Titan Text Embeddings V2 | **Kept self-hosted.** Same model already loaded for category suggestion; reusing it for the prohibited-item check costs nothing extra. |
| 4 | `cardiffnlp/twitter-roberta-base-sentiment-latest` | Amazon Comprehend — `DetectSentiment` | **Both built**, selected by `CAMPUSHUB_SENTIMENT_BACKEND` (§1.1). Default is local; Comprehend is a one-setting switch away, already wired, no training data needed. |
| 5 | `Falconsai/nsfw_image_detection` | Amazon Rekognition — `DetectModerationLabels` | **Kept self-hosted.** No Comprehend-style toggle was built for this one; Rekognition's broader taxonomy (drugs, weapons, alcohol, not just NSFW) remains the reason to revisit this if the moderation queue needs that coverage later. |

All of these are reachable from the same Lambda tier either way — switching any of them to a
managed API is an `boto3` call inside the existing handler, not a new compute layer.

---

## 3. Cost vs. benefit, and why self-hosted won for four of five

### 3.1 Pricing (verify before relying on — see caveats)

| Service | Rate | Free tier | Source |
|---|---|---|---|
| Comprehend `DetectSentiment` | $0.0001 per 100-char unit, 3-unit (300-char) minimum per request → **$0.0003/request minimum** | 50,000 units/month free for 12 months | [AWS Comprehend pricing](https://aws.amazon.com/comprehend/pricing/) |
| Rekognition `DetectModerationLabels` | ~$1.00 per 1,000 images (first 1M/month), decreasing at volume | 1,000 images/month free for 12 months | [AWS Rekognition pricing](https://aws.amazon.com/rekognition/pricing/) |
| Bedrock Titan Text Embeddings V2 | ~$0.02 per 1M input tokens (≈$0.00002/1K tokens) | No dedicated free tier | [AWS Bedrock pricing](https://aws.amazon.com/bedrock/pricing/) |
| Bedrock Titan Multimodal Embeddings G1 | Not confirmed by search — publicly cited figures (~$0.00006/image, ~$0.0008/1K text tokens) are **unverified estimates** | No dedicated free tier | Check [AWS Bedrock pricing](https://aws.amazon.com/bedrock/pricing/) directly |

**Region caveat (important given the PRD's ap-south-1 commitment):** Bedrock has been generally
available in Mumbai (ap-south-1) since May 2024, and Titan Multimodal Embeddings G1 / Titan Image
Generator G1 appear supported there. Titan Text Embeddings V2, however, shows up inconsistently
for ap-south-1 across AWS's own regional-support tables for some inference modes — meaning
real-time embedding calls might require routing to a different region (extra latency, and a
data-residency question the PRD's "deployed in Mumbai" assumption doesn't currently account for).
Comprehend `DetectSentiment` **is** confirmed available and in production use in ap-south-1 today
(§1.1). **Confirm current model availability in ap-south-1 via the Bedrock console's "Model
access" page before routing #1–#3 through Bedrock.**

### 3.2 Illustrative monthly cost, both paths

Assumptions for a ~6,000-student campus app (no real production traffic data exists yet — these
are rough, adjustable placeholders): 1,000 course reviews/month, 5,000 text-embedding calls/month
(category suggestion + prohibited-item check combined), 2,000 L&F photos/month needing similarity
matching, 5,000 Buy & Sell/L&F images/month needing moderation.

| Task | Self-hosted (Lambda compute only) | AWS-managed |
|---|---|---|
| Sentiment (1,000 reviews) | ~$0 (already-running Lambda, no extra model cost) — **this is the default** | ~$0.30/mo, but **$0 for 12 months** (well under the 50K free units) — a one-setting switch away |
| Text embedding (5,000 calls) | ~$0.01/mo (Lambda GB-seconds at ~0.2s/invocation, 1536MB) | ~$0.005/mo (250K tokens @ $0.02/1M) |
| Image embedding (2,000 photos) | ~$0.01/mo (included in matcher Lambda above) | ~$0.12/mo (estimate, unverified — see §3.1) |
| Image moderation (5,000 images) | ~$0.02/mo (included in matcher Lambda) — **this is what's deployed** | ~$5.00/mo, ~$4/mo after the 1,000-image/month free tier in year 1 |
| **Total** | **≈$0.05/month** | **≈$5.4/month** (less in year 1 with free tiers) |

Both totals are trivial against AWS Educate/free-tier credits (PRD NFR-5) — **cost alone didn't
decide this** at CampusHub's scale. The gap would only start to matter at a scale far beyond
IISc's ~6,000 students, which is explicitly out of the PRD's scope.

### 3.3 The factors that actually decided it

| Factor | Self-hosted model | AWS-managed |
|---|---|---|
| **Engineering effort** | All five are built, calibrated, in production use | Switching #1–#3 or #5 now would mean **throwing away working, tested code** (the matcher Lambda, `calibrate_matching.py`, `calibrate_category_suggest.py`, tuned thresholds from real benchmark data) for no functional gain |
| **Training data** | None of these five needed any CampusHub-specific fine-tuning — all are used off-the-shelf or with a calibrated threshold, not a trained classifier | Also zero training data needed — this was the strongest argument *for* a managed API before #4 and #5 were built, and it's exactly why #4 got both paths wired in |
| **Latency / dependency** | In-process inference, no network hop, no external service to be down | Adds a network round-trip to a regional AWS endpoint per call (typically tens to ~100+ms) and a new external dependency / potential throttling point |
| **Accuracy / maturity** | MiniLM, MobileCLIP and bge-small are well-benchmarked for their tasks and additionally calibrated on real CampusHub data (§4) | Comprehend and Rekognition are production-hardened on far larger, broader training sets |
| **Moderation coverage breadth** | Falconsai is a **binary** NSFW/safe classifier only | Rekognition's moderation taxonomy also flags **drugs, weapons, alcohol, violence** — overlapping the prohibited-item text check, not just the obscene-photo one; one managed call could partially cover two checks at once. This is the strongest open argument for revisiting #5. |
| **Licensing** | MobileCLIP-S0 is under Apple's ML research licence — fine for this course project; check before any commercial use | No model-licensing question for Comprehend/Rekognition — metered APIs, not weights downloads |
| **Vendor lock-in** | Portable — ONNX models run on any cloud or on-prem | Directly against the PRD's own stated reasoning for choosing Terraform over CloudFormation (§6.3: "prevents cloud vendor lock-in") — a Comprehend/Rekognition/Bedrock call is AWS-specific in a way a self-hosted ONNX model isn't |
| **Operational maturity for a student project** | Requires maintaining Docker images, ONNX runtimes, arm64 builds, model updates | Fully managed — no model lifecycle to own |

---

## 4. Accuracy and other quality metrics, by task

Cost was a wash at CampusHub's scale (§3), so accuracy is the other half of why self-hosted was
kept for #1, #2, #3 and #5. Published, comparable numbers are harder to find than the pricing
figures above — flagged per row below.

### 4.1 Text embedding: MiniLM vs. Titan Text Embeddings V2

| Model | Metric | Score | Source |
|---|---|---|---|
| `all-MiniLM-L6-v2` | MTEB overall average | ~56 (community-aggregated; not on the official model card) | [MTEB-Arena leaderboard metadata](https://huggingface.co/spaces/Nymbo/MTEB-Arena/raw/main/model_meta.py) |
| Titan Text Embeddings V2 | MTEB overall average | ~60.4 (**AWS-reported**) | [AWS Titan Text Embeddings V2 launch post](https://aws.amazon.com/blogs/machine-learning/get-started-with-amazon-titan-text-embeddings-v2-a-new-state-of-the-art-embeddings-model-on-amazon-bedrock/) |
| `all-MiniLM-L6-v2` | **CampusHub's own calibration** (20 real description pairs, 8 near-miss look-alikes, 364 unrelated pairs) | 14/20 true pairs alert, 1/8 look-alikes false-triggers, **0/364 unrelated pairs false-positive** | `backend/scripts/calibrate_matching.py` |
| Titan Text Embeddings V2 | CampusHub-specific calibration | **None exists** | — |

**Verdict:** On a generic, task-agnostic benchmark, Titan V2 edges out MiniLM (~60 vs. ~56 MTEB
average) — but MTEB mixes dozens of unrelated tasks, not CampusHub's specific job of short
listing-title/description nearest-neighbor matching. MiniLM has been measured on CampusHub's
*actual* data with a known false-positive rate (0/364); Titan has no equivalent. A real,
task-specific measurement beats a generic benchmark edge — this is why MiniLM stayed.

### 4.2 Image embedding: MobileCLIP-S0 vs. Titan Multimodal Embeddings G1

| Model | Metric | Score | Source |
|---|---|---|---|
| MobileCLIP-S0 | ImageNet-1K zero-shot top-1 | **67.8%** | [Apple `ml-mobileclip` repo](https://github.com/apple/ml-mobileclip) |
| MobileCLIP-S0 | Average across 38 zero-shot datasets | 58.1% | Apple `ml-mobileclip` repo / CVPR 2024 paper |
| MobileCLIP-S0 | **CampusHub's own calibration** (34 real lost-item photos) | Text↔photo alone is weak (CLIP score 0.1–0.35) and capped accordingly; photos add evidence on top of text matches | `backend/scripts/calibrate_matching.py` |
| Titan Multimodal Embeddings G1 | Any published zero-shot/retrieval accuracy | **None found** — AWS documents inputs, outputs and pricing, not accuracy | AWS Titan Multimodal Embeddings docs |

**Verdict:** Not close. MobileCLIP-S0 has a transparent, independently reproducible benchmark
suite (Apple's own repo + the CVPR 2024 paper) plus CampusHub-specific calibration on real photos.
Titan Multimodal Embeddings has **no publicly available accuracy benchmark at all** for this kind
of task — there's nothing to compare against, which if anything strengthens the case for keeping
MobileCLIP-S0.

### 4.3 Sentiment: RoBERTa (local backend) vs. Amazon Comprehend

| Model | Metric | Score | Source |
|---|---|---|---|
| `cardiffnlp/twitter-roberta-base-sentiment-latest` | Published benchmark on the model's own training distribution (tweets, 3-class) | Not re-measured on course-review text specifically | [HF model card](https://huggingface.co/cardiffnlp/twitter-roberta-base-sentiment-latest) |
| `cardiffnlp/twitter-roberta-base-sentiment-latest` | Off-the-shelf behaviour on CampusHub sentences (spot-checked) | Correctly scores a neutral fact ("Assignments are due every Friday") near 0 and a mixed sentence ("Great content, but the grading was opaque") as mildly positive — both of which the word-list scorer got wrong | `tests/test_sentiment_backends.py` |
| Amazon Comprehend `DetectSentiment` | Any AWS-published accuracy/precision/recall figure | **None published** | — |
| Amazon Comprehend `DetectSentiment` | Independent/anecdotal reports | Rated good on clear-cut phrasing, weaker on sarcasm in informal tests; one peer-reviewed 2024 paper benchmarks it against Azure AI Language on product reviews (figures not accessible here) | [Vonage sentiment API comparison](https://developer.vonage.com/en/blog/2019/10/17/sentiment-api-analysis-comparison-dr); *Big Data and Cognitive Computing* (2024), DOI 10.3390/bdcc8120166 |

**Verdict:** Neither side has a hard, CampusHub-specific accuracy number. This is exactly why both
got built instead of picking one on faith: `CAMPUSHUB_SENTIMENT_BACKEND` makes the choice a config
value, not a one-way architectural bet. The local model is the default because it's free and has
no external dependency; switching to Comprehend needs no code change if its anecdotal maturity
ever matters more than that.

### 4.4 Obscene image detection: Falconsai NSFW vs. Amazon Rekognition

| Model | Metric | Score | Source |
|---|---|---|---|
| `Falconsai/nsfw_image_detection` | Self-reported eval accuracy | **98.0%** (`eval_accuracy` 0.980375) | [HF model card](https://huggingface.co/Falconsai/nsfw_image_detection) — own ~80K-image proprietary eval set; class balance, subgroup results and false-positive rate are **not disclosed** |
| `Falconsai/nsfw_image_detection` | **CampusHub's own spot-check** (46 ordinary, non-obscene photos) | Highest nsfw probability seen: 0.004, against a flag threshold of 0.8 — a wide margin | `app/matching/nsfw.py` |
| Amazon Rekognition `DetectModerationLabels` | Independent third-party benchmark (sexually-suggestive image detection) | ~95.0% correct (5.0% error rate), vs. Google Cloud Vision's 97.5% (2.5% error) on the same set | [Sightengine comparison study](https://medium.com/sightengine/benchmarking-google-vision-amazon-rekognition-microsoft-azure-on-image-moderation-73909739b8b4) (undated, single dataset, custom label mapping) |
| Amazon Rekognition | AWS's own published precision/recall | **None** — AWS publishes a self-measurement *methodology* (build your own labeled set, sweep `MinConfidence`), not a number | [AWS — metrics for evaluating content moderation](https://aws.amazon.com/blogs/machine-learning/metrics-for-evaluating-content-moderation-in-amazon-rekognition-and-other-content-moderation-services) |

**Verdict:** Falconsai's 98% nominally beats Rekognition's ~95% from the one independent study
found — but Falconsai's number is self-reported on an undisclosed proprietary eval set, while
Rekognition's ~95% comes from an independent third party using a different, also-undisclosed
methodology. **These aren't on equal footing** and shouldn't be read as a clean 3-point gap.
CampusHub's own spot-check (0.004 on 46 ordinary photos) is reassuring on false positives but far
too small a sample to be a real accuracy measurement. This was built self-hosted on the strength
of §3's effort case, not a confident accuracy win — it remains the least-certain comparison in
this doc, and Rekognition's broader taxonomy (§3.3) is the concrete reason to re-test before
treating the current choice as final.

### 4.5 Summary

| Task | Self-hosted evidence | Managed evidence | Directly comparable? | Final call |
|---|---|---|---|---|
| Text embedding | MiniLM: ~56 MTEB + real CampusHub calibration (0/364 false positives) | Titan V2: ~60 MTEB (AWS-reported), no CampusHub calibration | No — benchmark vs. real calibration | Kept MiniLM |
| Image embedding | MobileCLIP-S0: 67.8% ImageNet zero-shot + real calibration | Titan Multimodal: no published benchmark | No — one side has no data | Kept MobileCLIP-S0 |
| Category suggestion / prohibited-item text | bge-small-en-v1.5: calibrated threshold + lead (0.52 / 0.03), 15/19 recall on illegal titles | Titan V2: no CampusHub calibration | No | Kept bge-small |
| Sentiment | RoBERTa: correct on spot-checked neutral/mixed sentences, no formal benchmark | Comprehend: no published number, anecdotal only | No — neither has a real number | **Both built**, local is default |
| Obscene image | Falconsai: 98% (self-reported, undisclosed eval set) + 0.004 on 46 CampusHub photos | Rekognition: ~95% (independent, different eval set) | Weakly — different methodologies | Kept self-hosted, but weakest-evidence call of the five |

The pattern across all five: wherever CampusHub did real, task-specific measurement (text and
image embedding, category suggestion), that evidence clearly beat a generic benchmark and the
self-hosted model stayed. Wherever nothing was measured on a comparable footing (sentiment,
obscene image), the decision rested on engineering effort and operational simplicity, not
accuracy — and sentiment resolved that by building both paths instead of picking one.

---

## 5. Current status and when to revisit

**Four of five models stayed self-hosted; one ships both paths behind a setting.** This wasn't a
blanket "self-hosted is better" conclusion — it's what each model's own evidence supported:

| # | Model | Status | Revisit if... |
|---|---|---|---|
| 1 | Text embedding (MiniLM) | Self-hosted, in production | Traffic grows enough that cost stops being negligible, or Bedrock's ap-south-1 availability for this model firms up and simplifies ops |
| 2 | Image embedding (MobileCLIP-S0) | Self-hosted, in production | A future *commercial* deployment makes Apple's ML research licence a blocker — Titan Multimodal Embeddings would be the fallback then |
| 3 | Category suggestion / prohibited-item text (bge-small) | Self-hosted, in production, reused across two features | Same as #1 |
| 4 | Course-feedback sentiment | **Both built.** Local model is the default; Comprehend is one setting away (`CAMPUSHUB_SENTIMENT_BACKEND=comprehend`) | Almost never — the switch already exists; flip it if the local model's accuracy on real course reviews turns out weaker than expected |
| 5 | Obscene-image detection | Self-hosted, in production | A moderator wants broader coverage (drugs/weapons/alcohol in photos, not just NSFW) — Rekognition's taxonomy would add that for ~$4–5/month at CampusHub's volume, and this is the comparison with the thinnest accuracy evidence of the five (§4.4) |

The one hard blocker to resolve before routing *any* of #1–#3 or #5 through Bedrock/Rekognition is
confirming current model/API availability and quota limits in ap-south-1 via the AWS console, and
re-checking actual current pricing on the official pages linked above — the figures here are
directionally correct but not independently verified against AWS's live pricing pages.

---

## Caveats

- Pricing figures above come from third-party aggregators and AWS marketing pages found via web
  search, **not AWS's live pricing calculator** — confirm exact current rates before budgeting.
- Volume assumptions in §3.2 are illustrative placeholders (no real CampusHub production traffic
  data exists yet) — swap in real numbers once there's traffic to measure.
- Bedrock Titan Multimodal Embeddings pricing specifically could not be confirmed from search
  results and should be treated as a rough placeholder, not a quote.
- This doc compares the self-hosted model already chosen for each task against the AWS-managed
  alternative for that same task; it doesn't re-litigate the choice of *which* self-hosted model
  (MiniLM vs. e5-small, RoBERTa vs. DeBERTa, etc.) beyond the reasoning already in §1 and §4.

## Sources

- [AWS Comprehend pricing](https://aws.amazon.com/comprehend/pricing/)
- [AWS Rekognition pricing](https://aws.amazon.com/rekognition/pricing/)
- [AWS Bedrock pricing](https://aws.amazon.com/bedrock/pricing/)
- [Amazon Titan Text Embeddings V2 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-titan-text-embeddings-v2-2.md)
- [Business Standard — AWS Bedrock launches in Mumbai region, May 2024](https://business-standard.com/companies/news/amazon-web-services-launches-genai-service-bedrock-in-apac-mumbai-region-124051501252_1.html)
- [AWS Bedrock — supported Regions and models for model copy](https://docs.aws.amazon.com/bedrock/latest/userguide/copy-model-support.html)

*Figures above are third-party/vendor-reported, not verified against AWS's live pricing or
regional-availability pages — treat as directional until confirmed.*

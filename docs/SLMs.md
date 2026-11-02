# SLMs: AWS-Managed Alternatives & Cost-Benefit Analysis

*As-of 1 Nov 2026 — advisory only, nothing below is implemented. Companion doc to
[future-plan-2026-10-31-next-level-features.md](future-plan-2026-10-31-next-level-features.md) §4,
which this doc does not repeat except to summarize.*

This doc answers one question: for each of the four small models (SLMs) the future-plan doc
proposes self-hosting, what's the AWS-managed equivalent, and is switching to it actually worth it
— in dollars, latency, engineering effort, and risk — for a project this size, built on the
AWS stack the [PRD](CampusHub-PRD-v1.pdf) already committed to (Lambda, API Gateway, RDS, S3,
Cognito, ap-south-1/Mumbai)?

---

## 1. What the future plan proposes (recap)

| # | Model | Params / size | Task | Status (per future-plan doc) |
|---|---|---|---|---|
| 1 | `all-MiniLM-L6-v2` | 22M / ~90MB | Text-embedding similarity — L&F description matching, first-pass illegal-item text check | **Built & calibrated (1 Nov 2026)** |
| 1b | `bge-small-en-v1.5` (int8) | 33M / 34MB | Category auto-suggest from a listing title | **Built & calibrated (1 Nov 2026)** |
| 2 | `MobileCLIP-S0` | ~11–12M image encoder / tens of MB | Image-embedding similarity — L&F photo matching + text↔photo matching | **Built & calibrated (1 Nov 2026)** |
| 3 | `microsoft/deberta-v3-xsmall` (fine-tuned) | ~70M | Course-review sentiment classification, replacing the lexicon scorer | **Not built** — lexicon scorer (`app/sentiment.py`) still in place |
| 4 | `Falconsai/nsfw_image_detection` | ViT, ~87MB (INT8) | Obscene-image detection for automatic flagging | **Not built** — §1.6 automatic flagging not implemented |

That build/not-built split matters a lot for the recommendation in §5 — two of these already exist
as tested, calibrated, working code; two are still green-field.

**Update (1 Nov 2026, later):** category auto-suggestion (`backend/app/categories_suggest.py`,
future-plan §2.4) first reused MiniLM on bare category names with a 0.2 threshold, and it made bad
suggestions (e.g. "plant" → "Bottle" when there was no Plant category). It now uses its own small
model, **`BAAI/bge-small-en-v1.5` (int8 ONNX, 34 MB, MIT, ~3 ms per title)**, in the API itself.
Each category is scored as a phrase ("a <name> item for sale") blended with its recent listings, and
a suggestion needs a calibrated score and a clear lead over the runner-up
(`scripts/calibrate_category_suggest.py`). So the footprint is now five small models, not four. The
AWS alternative for it is still Titan Text Embeddings V2, with the same trade-offs as §3.

**Update (3 Nov 2026): reading mess menus (OCR).** Mess committees share the month's menu as a PDF
or photo, usually a scanned table. `backend/app/mess_extract.py` prefills the menu form from it:
pypdfium2 renders the page, the table's ruled lines are found with plain numpy, and each cell is read
by **Tesseract 5** (`tesseract` program, LSTM English model ~4 MB, Apache-2.0), three ways per cell
(grey and two colour thresholds, since veg/non-veg items are printed in colour) keeping the cleanest
reading. On the sample C Mess menu it reads all 28 meals and the "every day" rows in ~5 s; a few words
per page come out misspelt ("Matta nce"), which is why the moderator always reviews the table before
posting. Nothing is posted automatically.

We also tried **RapidOCR** (PaddleOCR's det/rec models as ONNX, ~15 MB, on the onnxruntime we already
ship): it deploys more easily on Lambda but ran words together on this menu ("ChapatiMattaceRamei"),
so Tesseract won. The AWS-managed alternative is **Amazon Textract** (`AnalyzeDocument` with TABLES):
it returns the table cells directly and reads coloured text well, at about **$0.015 per page** (tables)
— a few dollars a year for ~10 messes posting monthly — with no binary to package. It is the natural
choice if the API stays on Lambda, where Tesseract needs a layer; the code would swap `_read_cell` and
the grid detection for one Textract call and keep the same review step.

---

## 2. AWS-native alternative for each

| # | Self-hosted SLM | AWS-managed alternative | What it is |
|---|---|---|---|
| 1 | `all-MiniLM-L6-v2` | **Amazon Bedrock — Titan Text Embeddings V2** | Managed text-embedding API; same "embed and cosine-compare" pattern, no self-hosted weights. |
| 2 | `MobileCLIP-S0` | **Amazon Bedrock — Titan Multimodal Embeddings G1** | Managed model embedding text *and* images into one shared vector space — covers both the photo↔photo and text↔photo matching MobileCLIP does. |
| 3 | `deberta-v3-xsmall` | **Amazon Comprehend — DetectSentiment** | Fully managed sentiment API (Positive/Negative/Neutral/Mixed), no training or fine-tuning required. |
| 4 | `Falconsai/nsfw_image_detection` | **Amazon Rekognition — DetectModerationLabels (Image Moderation)** | Fully managed image-moderation API with a broad taxonomy (nudity, violence, drugs, weapons, alcohol, gore, etc.), not just a binary NSFW flag. |

All four are reachable from the Lambda tier the PRD already specs, so no new compute layer is
needed either way — only the call inside the Lambda function changes (in-process model inference
vs. an outbound `boto3` call to a managed API).

---

## 3. Cost vs. benefit analysis

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
**Confirm current model availability in ap-south-1 via the Bedrock console's "Model access" page
before committing to this path** — this is a deploy-blocking risk, not a pricing detail.

### 3.2 Illustrative monthly cost, both paths

Assumptions for a ~6,000-student campus app (no real traffic data exists yet — these are rough,
adjustable placeholders, not measured): 1,000 course reviews/month, 5,000 text-embedding calls/month
(listing/report creation + category suggestion + illegal-text check combined), 2,000 L&F photos/month
needing similarity matching, 5,000 Buy & Sell/L&F images/month needing moderation.

| Task | Self-hosted (Lambda compute only) | AWS-managed |
|---|---|---|
| Sentiment (1,000 reviews) | ~$0 (already-running Lambda, no extra model cost) | ~$0.30/mo — but **$0 for 12 months** (well under the 50K free units) |
| Text embedding (5,000 calls) | ~$0.01/mo (Lambda GB-seconds at ~0.2s/invocation, 1536MB) | ~$0.005/mo (250K tokens @ $0.02/1M) |
| Image embedding (2,000 photos) | ~$0.01/mo (included in matcher Lambda above) | ~$0.12/mo (estimate, unverified — see 3.1) |
| Image moderation (5,000 images) | Not built yet — would add similar Lambda compute, ~$0.02/mo | ~$5.00/mo, **~$4/mo after the 1,000-image/month free tier** in year 1 |
| **Total** | **≈$0.05/month** | **≈$5.4/month** (less in year 1 with free tiers) |

Both totals are trivial against AWS Educate/free-tier credits (PRD NFR-5) — **cost alone does not
decide this** at CampusHub's scale. The gap would only start to matter at a scale far beyond IISc's
~6,000 students (e.g. a multi-campus deployment), which is explicitly out of the PRD's scope (§2.3).

### 3.3 The factors that actually decide it

| Factor | Self-hosted SLM | AWS-managed |
|---|---|---|
| **Engineering effort — already built items (#1, #2)** | Zero — done, calibrated, in production use since 1 Nov | Would mean **throwing away working, tested code** (the matcher Lambda, `calibrate_matching.py`, tuned thresholds from real benchmark data) for no functional gain |
| **Engineering effort — not-yet-built items (#3, #4)** | Needs labeled training data to fine-tune (explicitly flagged as a blocker in the future-plan doc: *"would need fine-tuning on review-style text... rather than being used off-the-shelf"*) + a new Lambda/model-hosting setup | **Zero training data needed** — both are call-and-get-a-label APIs. This is the strongest case for going managed. |
| **Latency / dependency** | In-process inference, no network hop, no external service to be down | Adds a network round-trip to a regional AWS endpoint per call (typically tens to ~100+ms) and a new external dependency / potential throttling point |
| **Accuracy / maturity** | MiniLM/MobileCLIP are well-benchmarked for their tasks; DeBERTa/Falconsai would need validation CampusHub hasn't done yet | Comprehend and Rekognition are production-hardened on far larger, broader training sets — likely *more* robust out of the box than a small fine-tuned model with no labeled CampusHub data |
| **Moderation coverage breadth** | Falconsai is a **binary** NSFW/safe classifier only | Rekognition's moderation taxonomy also flags **drugs, weapons, alcohol, violence** — meaningful overlap with §1.6 check (a) (illegal items), not just check (d) (obscene images); one managed call could partially cover two of the four automatic-flagging checks |
| **Licensing** | MobileCLIP-S0 is under Apple's ML research licence — fine for this course project, but the future-plan doc itself flags "check it before any commercial use" | No model-licensing question — it's a metered API, not a weights download |
| **Vendor lock-in** | Portable — ONNX models run on any cloud or on-prem | Directly against the PRD's **own stated reasoning for choosing Terraform over CloudFormation** (§6.3: "prevents cloud vendor lock-in") — a Comprehend/Rekognition/Bedrock call is AWS-specific in a way a self-hosted ONNX model isn't |
| **Operational maturity for a student project** | Requires maintaining Docker images, ONNX runtimes, arm64 builds, model updates | Fully managed — no model lifecycle to own at all |

---

## 4. Accuracy and other quality metrics, by task

Cost is a wash at CampusHub's scale (§3), so accuracy is the other half of the decision. Published,
comparable numbers are harder to find than the pricing figures above — flagged per row below.

### 4.1 Text embedding: MiniLM vs. Titan Text Embeddings V2

| Model | Metric | Score | Source |
|---|---|---|---|
| `all-MiniLM-L6-v2` | MTEB overall average | ~56 (community-aggregated; not on the official model card) | [MTEB-Arena leaderboard metadata](https://huggingface.co/spaces/Nymbo/MTEB-Arena/raw/main/model_meta.py) |
| Titan Text Embeddings V2 | MTEB overall average | ~60.4 (**AWS-reported**) | [AWS Titan Text Embeddings V2 launch post](https://aws.amazon.com/blogs/machine-learning/get-started-with-amazon-titan-text-embeddings-v2-a-new-state-of-the-art-embeddings-model-on-amazon-bedrock/) |
| `all-MiniLM-L6-v2` | **CampusHub's own calibration** (20 real description pairs, 8 near-miss look-alikes, 364 unrelated pairs) | 14/20 true pairs alert, 1/8 look-alikes false-triggers, **0/364 unrelated pairs false-positive** | `backend/scripts/calibrate_matching.py`, future-plan §1.2 |
| Titan Text Embeddings V2 | CampusHub-specific calibration | **None exists** | — |

**Verdict:** On a generic, task-agnostic benchmark, Titan V2 edges out MiniLM (~60 vs. ~56 MTEB
average) — but MTEB mixes dozens of unrelated tasks (retrieval, clustering, classification), not
CampusHub's specific job of short listing-title/description nearest-neighbor matching. MiniLM has
already been measured on CampusHub's *actual* data with a known false-positive rate (0/364); Titan
has no equivalent. A real, task-specific measurement beats a generic benchmark edge here — accuracy
does not change the §5 recommendation to keep MiniLM.

### 4.2 Image embedding: MobileCLIP-S0 vs. Titan Multimodal Embeddings G1

| Model | Metric | Score | Source |
|---|---|---|---|
| MobileCLIP-S0 | ImageNet-1K zero-shot top-1 | **67.8%** | [Apple `ml-mobileclip` repo](https://github.com/apple/ml-mobileclip) |
| MobileCLIP-S0 | Average across 38 zero-shot datasets | 58.1% | Apple `ml-mobileclip` repo / CVPR 2024 paper |
| MobileCLIP-S0 | **CampusHub's own calibration** (34 real lost-item photos) | Text↔photo alone is weak (CLIP score 0.1–0.35) and capped accordingly; photos add evidence on top of text matches | future-plan §1.2 |
| Titan Multimodal Embeddings G1 | Any published zero-shot/retrieval accuracy | **None found** — AWS documents inputs, outputs and pricing, not accuracy | AWS Titan Multimodal Embeddings docs |

**Verdict:** Not close. MobileCLIP-S0 has a transparent, independently reproducible benchmark suite
(Apple's own repo + the CVPR 2024 paper) plus CampusHub-specific calibration on real photos. Titan
Multimodal Embeddings has **no publicly available accuracy benchmark at all** for this kind of task
— there's nothing to compare against. Accuracy does not change the recommendation to keep
MobileCLIP-S0; if anything it strengthens it, since Titan's performance here is simply unknown.

### 4.3 Sentiment: DeBERTa-v3-xsmall vs. Amazon Comprehend

| Model | Metric | Score | Source |
|---|---|---|---|
| `deberta-v3-small` (closest published proxy — xsmall itself has no published fine-tuned number), fine-tuned on SST-2 | GLUE SST-2 validation accuracy | 94.0% (F1 94.2%) | [HF model card, community fine-tune](https://huggingface.co/mrm8488/deberta-v3-small-finetuned-sst2) |
| `deberta-v3-xsmall` | Accuracy on course-review-style text, fine-tuned | **None — doesn't exist yet**, per the future-plan doc itself: *"would need fine-tuning on review-style text... rather than being used off-the-shelf"* | future-plan §4.1 |
| Amazon Comprehend `DetectSentiment` | Any AWS-published accuracy/precision/recall figure | **None published** | — |
| Amazon Comprehend `DetectSentiment` | Independent/anecdotal reports | Rated good on clear-cut phrasing, weaker on sarcasm in informal tests; one peer-reviewed 2024 paper benchmarks it against Azure AI Language on product reviews (figures not accessible here) | [Vonage sentiment API comparison](https://developer.vonage.com/en/blog/2019/10/17/sentiment-api-analysis-comparison-dr); *Big Data and Cognitive Computing* (2024), DOI 10.3390/bdcc8120166 |

**Verdict:** Neither side has a hard, CampusHub-relevant number today. The DeBERTa-v3 family is
well-validated on GLUE generally (94% for the small variant on SST-2), suggesting xsmall would land
a few points lower but still strong — *contingent on* fine-tuning CampusHub doesn't have data for yet.
Comprehend has **zero published accuracy figure**; what exists is anecdotal and mixed. Accuracy is
roughly a wash — it doesn't override §3's engineering-effort case for Comprehend (no training data
required), nor does it strengthen it; the recommendation rests on effort, not accuracy.

### 4.4 Obscene image detection: Falconsai NSFW vs. Amazon Rekognition

| Model | Metric | Score | Source |
|---|---|---|---|
| `Falconsai/nsfw_image_detection` | Self-reported eval accuracy | **98.0%** (`eval_accuracy` 0.980375) | [HF model card](https://huggingface.co/Falconsai/nsfw_image_detection) — own ~80K-image proprietary eval set; class balance, subgroup results and false-positive rate are **not disclosed** |
| Amazon Rekognition `DetectModerationLabels` | Independent third-party benchmark (sexually-suggestive image detection) | ~95.0% correct (5.0% error rate), vs. Google Cloud Vision's 97.5% (2.5% error) on the same set | [Sightengine comparison study](https://medium.com/sightengine/benchmarking-google-vision-amazon-rekognition-microsoft-azure-on-image-moderation-73909739b8b4) (undated, single dataset, custom label mapping) |
| Amazon Rekognition | AWS's own published precision/recall | **None** — AWS publishes a self-measurement *methodology* (build your own labeled set, sweep `MinConfidence`), not a number | [AWS — metrics for evaluating content moderation](https://aws.amazon.com/blogs/machine-learning/metrics-for-evaluating-content-moderation-in-amazon-rekognition-and-other-content-moderation-services) |

**Verdict:** Falconsai's 98% nominally beats Rekognition's ~95% from the one independent study found
— but Falconsai's number is self-reported on an undisclosed proprietary eval set (a vendor grading
its own homework), while Rekognition's ~95% comes from an independent third party using a different,
also-undisclosed methodology. **These are not on equal footing** and shouldn't be read as a clean
3-point gap. Given that, and that this feature isn't built yet, accuracy doesn't clearly override
§3's effort-and-coverage case for Rekognition (zero fine-tuning, broader taxonomy covering
drugs/weapons/alcohol too) — but it's also not a confident accuracy win for Rekognition either;
treat this one as the least-certain comparison in this doc and worth a real side-by-side test on
CampusHub's own uploaded images before fully committing either way.

### 4.5 Summary

| Task | Self-hosted evidence | Managed evidence | Directly comparable? | Does accuracy change §5's call? |
|---|---|---|---|---|
| Text embedding | MiniLM: ~56 MTEB + real CampusHub calibration (0/364 false positives) | Titan V2: ~60 MTEB (AWS-reported), no CampusHub calibration | No — benchmark vs. real calibration | No — keep MiniLM |
| Image embedding | MobileCLIP-S0: 67.8% ImageNet zero-shot + real calibration | Titan Multimodal: no published benchmark | No — one side has no data | No — keep MobileCLIP-S0 |
| Sentiment | DeBERTa-v3 family: ~94% SST-2 (proxy, not fine-tuned for course reviews yet) | Comprehend: no published number, anecdotal only | No — neither has a real number yet | No — Comprehend still wins on effort |
| Obscene image | Falconsai: 98% (self-reported, undisclosed eval set) | Rekognition: ~95% (independent, different eval set) | Weakly — different methodologies | No — Rekognition still wins on effort, but re-test before committing |

The pattern across all four: wherever CampusHub has already done real, task-specific measurement
(text and image embedding), that evidence is stronger than any generic benchmark and the
self-hosted model should stay. Wherever nothing has been measured yet (sentiment, obscene image),
neither side has a trustworthy accuracy edge, so the §3 engineering-effort argument — not accuracy
— is what should actually decide it.

---

## 5. Recommendation

**Don't treat this as one blanket "AWS vs. self-hosted" decision — the deciding variable per model
is whether it's already built, not which approach is abstractly better.**

| # | Model | Recommendation | Why |
|---|---|---|---|
| 1 | Text embedding (MiniLM) | **Keep self-hosted.** No reason to touch it. | Already built, calibrated against real data (20 description pairs, 8 look-alikes), Apache-2.0 licensed, zero marginal cost, avoids a new external dependency and avoids the Bedrock ap-south-1 availability risk in §3.1 entirely. Category auto-suggestion moved to bge-small-en-v1.5 (see the update note in §1). |
| 2 | Image embedding (MobileCLIP-S0) | **Keep self-hosted.** | Same reasoning — already built and calibrated (34 photos), already flagged as coursework-fine on licensing. Revisit only if a future *commercial* deployment makes Apple's ML research licence a blocker — Titan Multimodal Embeddings would be the fallback then. |
| 3 | Sentiment classifier | **Switch to Amazon Comprehend `DetectSentiment`.** | Not built yet, and the future-plan doc's own blocker — needing labeled review data to fine-tune DeBERTa — disappears entirely with a managed API. Comprehend is also what `app/sentiment.py`'s own docstring already anticipated as the eventual drop-in replacement. Cost is $0 for 12 months at CampusHub's volume. |
| 4 | Obscene-image detection | **Switch to Amazon Rekognition `DetectModerationLabels`.** | Not built yet, avoids standing up a new model-hosting Lambda from scratch, and its broader taxonomy (drugs/weapons/alcohol, not just NSFW) gives partial coverage of §1.6 check (a) for free. The ~$4–5/month cost at estimated volume is immaterial against AWS Educate credits, and this check already runs async per the future-plan's routing recommendation, so the extra network latency doesn't affect perceived UX either way. |

**Overall verdict**: a **hybrid approach** — self-hosted for the two features that are already
shipped and working, AWS-managed for the two that are still green-field. This isn't a compromise
for its own sake: it's the option that discards zero working code, requires zero new training data
for the hardest-to-fine-tune pieces, and keeps cost negligible under either path at CampusHub's
scale. The one hard blocker to resolve before committing to #3/#4 is confirming current Comprehend
and Rekognition (not just Bedrock) model/API availability and quota limits in ap-south-1 via the
AWS console, and re-checking actual current pricing on the official pages linked above — the figures
here are directionally correct but not independently verified against AWS's live pricing pages.

---

## Caveats

- Pricing figures above come from third-party aggregators and AWS marketing pages found via web
  search, **not AWS's live pricing calculator** — confirm exact current rates before budgeting.
- Volume assumptions in §3.2 are illustrative placeholders (no real CampusHub usage data exists
  yet) — swap in real numbers once there's traffic to measure.
- Bedrock Titan Multimodal Embeddings pricing specifically could not be confirmed from search
  results and should be treated as a rough placeholder, not a quote.
- This analysis does not re-litigate §4 of the future-plan doc's model *choice* (MiniLM vs.
  e5-small, DeBERTa vs. RoBERTa, etc.) — it only compares the self-hosted approach already decided
  there against the AWS-managed alternative for the same task.

## Sources

- [AWS Comprehend pricing](https://aws.amazon.com/comprehend/pricing/)
- [AWS Rekognition pricing](https://aws.amazon.com/rekognition/pricing/)
- [AWS Bedrock pricing](https://aws.amazon.com/bedrock/pricing/)
- [Amazon Titan Text Embeddings V2 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-titan-text-embeddings-v2-2.md)
- [Business Standard — AWS Bedrock launches in Mumbai region, May 2024](https://business-standard.com/companies/news/amazon-web-services-launches-genai-service-bedrock-in-apac-mumbai-region-124051501252_1.html)
- [AWS Bedrock — supported Regions and models for model copy](https://docs.aws.amazon.com/bedrock/latest/userguide/copy-model-support.html)

*Figures above are third-party/vendor-reported, not verified against AWS's live pricing or
regional-availability pages — treat as directional until confirmed.*

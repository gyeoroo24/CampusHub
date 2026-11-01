"""Download the small ONNX models at pinned revisions: Lost & Found matching (app/matching/models.py),
category suggestion and text flagging (app/categories_suggest.py, app/screening.py), and the
obscene-photo check (app/matching/nsfw.py).

    python scripts/fetch_match_models.py [target_dir]               # default: backend/models
    python scripts/fetch_match_models.py --suggest-only [target_dir] # just the category-suggestion model (API image)

Each file is checked against its SHA-256, so a changed upload on Hugging Face can't slip in.
Licences: all-MiniLM-L6-v2 and Falconsai nsfw_image_detection are Apache-2.0, bge-small-en-v1.5 is MIT. MobileCLIP-S0 weights are under
Apple's ML research licence (fine for this course project; check it before any commercial use).
"""
import hashlib
import pathlib
import sys
import urllib.request

MINILM = ("sentence-transformers/all-MiniLM-L6-v2", "1110a243fdf4706b3f48f1d95db1a4f5529b4d41")
MOBILECLIP = ("Xenova/mobileclip_s0", "757d59c9c6870a76a4b0306f05f5061bca15c39f")
BGE = ("Xenova/bge-small-en-v1.5", "ea104dacec62c0de699686887e3f920caeb4f3e3")   # category suggestion
NSFW = ("onnx-community/nsfw_image_detection-ONNX", "1ceb3c7fe1e9f3f2507e6df577437f23a9149fd5")   # obscene photos

FILES = [  # (repo, revision, path in repo, local path, sha256)
    (*MINILM, "onnx/model.onnx", "all-MiniLM-L6-v2/onnx/model.onnx",
     "6fd5d72fe4589f189f8ebc006442dbb529bb7ce38f8082112682524616046452"),
    (*MINILM, "tokenizer.json", "all-MiniLM-L6-v2/tokenizer.json",
     "be50c3628f2bf5bb5e3a7f17b1f74611b2561a3a27eeab05e5aa30f411572037"),
    (*MOBILECLIP, "onnx/vision_model.onnx", "mobileclip_s0/onnx/vision_model.onnx",
     "17d3c037b1d488c10c50e09f6009ea5a198caef4e0e8f4ea5617b7cb2d067ac0"),
    (*MOBILECLIP, "onnx/text_model.onnx", "mobileclip_s0/onnx/text_model.onnx",
     "f6e9bd5742bfc515889e901634d8a2ff2a57fab8564e4ad3760e800b1a51b77c"),
    (*MOBILECLIP, "tokenizer.json", "mobileclip_s0/tokenizer.json",
     "72ed5c96db5729294468543e4bc75fce14ca63f58e37300290189ba1c1e52b85"),
    (*BGE, "onnx/model_quantized.onnx", "bge-small-en-v1.5/onnx/model_quantized.onnx",
     "6c9c6101a956d62dfb5e7190c538226c0c5bb9cb27b651234b6df063ee7dbfe4"),
    (*BGE, "tokenizer.json", "bge-small-en-v1.5/tokenizer.json",
     "d241a60d5e8f04cc1b2b3e9ef7a4921b27bf526d9f6050ab90f9267a1f9e5c66"),
    (*NSFW, "onnx/model_int8.onnx", "nsfw_image_detection/onnx/model_int8.onnx",
     "bdc941491cd09ae75c5f40b038a5cd64482fa4e2b5297747323c5cda31303920"),
]
SUGGEST_ONLY = {"bge-small-en-v1.5/onnx/model_quantized.onnx", "bge-small-en-v1.5/tokenizer.json"}


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    args = sys.argv[1:]
    suggest_only = "--suggest-only" in args
    args = [a for a in args if a != "--suggest-only"]
    target = pathlib.Path(args[0] if args else pathlib.Path(__file__).parents[1] / "models")
    for repo, rev, remote, local, digest in FILES:
        if suggest_only and local not in SUGGEST_ONLY:
            continue
        dest = target / local
        if dest.is_file() and sha256(dest) == digest:
            print(f"ok       {local}")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_suffix(dest.suffix + ".part")
        print(f"download {local}")
        urllib.request.urlretrieve(f"https://huggingface.co/{repo}/resolve/{rev}/{remote}", tmp)
        if sha256(tmp) != digest:
            tmp.unlink()
            sys.exit(f"{local}: checksum mismatch, refusing to use it")
        tmp.replace(dest)
    print(f"Models ready in {target}")


if __name__ == "__main__":
    main()

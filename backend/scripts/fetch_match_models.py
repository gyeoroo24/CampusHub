"""Download the Lost & Found matching models (app/matching/models.py) at pinned revisions.

    python scripts/fetch_match_models.py [target_dir]     # default: backend/models

Each file is checked against its SHA-256, so a changed upload on Hugging Face can't slip in.
Licences: all-MiniLM-L6-v2 is Apache-2.0. MobileCLIP-S0 weights are under Apple's ML research
licence (fine for this course project; check it before any commercial use).
"""
import hashlib
import pathlib
import sys
import urllib.request

MINILM = ("sentence-transformers/all-MiniLM-L6-v2", "1110a243fdf4706b3f48f1d95db1a4f5529b4d41")
MOBILECLIP = ("Xenova/mobileclip_s0", "757d59c9c6870a76a4b0306f05f5061bca15c39f")

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
]


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> None:
    target = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).parents[1] / "models")
    for repo, rev, remote, local, digest in FILES:
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

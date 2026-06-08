---
name: remove-ai-watermarks
description: >-
  Strip visible AI watermarks (Gemini / Nano Banana sparkle, Doubao "豆包AI生成",
  Jimeng "★ 即梦AI", Samsung Galaxy AI strip), invisible watermarks (SynthID,
  StableSignature, TreeRing — diffusion regeneration, needs GPU), and AI
  provenance metadata (C2PA Content Credentials, EXIF/XMP "Made with AI",
  IPTC AISystemUsed, China TC260 AIGC label) from AI-generated images via the
  `remove-ai-watermarks` Python CLI. Also identifies the origin platform and
  watermark inventory of an image (`identify` subcommand). Use when the user
  asks to "remove AI watermark", "strip SynthID", "clean C2PA / Content
  Credentials", "remove Made-with-AI label", "去除 AI 水印", "去水印", "抹掉
  豆包 / 即梦 / Gemini 水印", "脱掉 AI 标签", or to inspect an image's AI
  origin / provenance.
---

# remove-ai-watermarks

Thin wrapper around the [`wiltodelta/remove-ai-watermarks`](https://github.com/wiltodelta/remove-ai-watermarks)
Python CLI. Visible-watermark removal and metadata stripping are CPU-only;
invisible-watermark removal (SynthID etc.) does diffusion regeneration and
wants a GPU.

## Install (once per machine, Python ≥ 3.10)

```bash
# Base: visible removal + metadata strip + identify
pipx install "git+https://github.com/wiltodelta/remove-ai-watermarks.git"
#   upgrade later:  pipx upgrade remove-ai-watermarks

# Optional extras — install only if needed:
pipx install "remove-ai-watermarks[gpu]       @ git+https://github.com/wiltodelta/remove-ai-watermarks.git"  # invisible removal
pipx install "remove-ai-watermarks[detect]    @ git+https://github.com/wiltodelta/remove-ai-watermarks.git"  # identify SD/SDXL/FLUX
pipx install "remove-ai-watermarks[trustmark] @ git+https://github.com/wiltodelta/remove-ai-watermarks.git"  # decode Adobe TrustMark
pipx install "remove-ai-watermarks[lama]      @ git+https://github.com/wiltodelta/remove-ai-watermarks.git"  # big-LaMa for `erase`
```

`uv tool install <same spec>` also works. First `invisible` run downloads
~2 GB of diffusion weights into the HF cache.

## Subcommands

| Subcommand | Use for | GPU |
|---|---|---|
| `identify <img> [--json]` | Source platform + watermark inventory (C2PA, IPTC, EXIF, SynthID proxy, visible marks). Reports `unknown`, never "clean". | no |
| `visible <img> -o <out>` | Known visible mark. `--mark auto` (default) detects; force `--mark gemini\|doubao\|jimeng\|samsung`. Reverse-alpha, true-pixel recovery. | no |
| `erase <img> --region x,y,w,h -o <out>` | Any region / arbitrary logo. cv2 inpaint default; `--backend lama` for big-LaMa. | no |
| `metadata <img> --check` / `--remove` | C2PA, EXIF, PNG text chunks, XMP, IPTC. `--check` also flags SynthID-bearing C2PA signers (Google / OpenAI). | no |
| `invisible <img> -o <out>` | SynthID / StableSignature / TreeRing via diffusion regen. Useful flags: `--humanize 4.0 --unsharp 0.5`, `--pipeline controlnet`, `--restore-faces`, `--auto` (let it pick). | yes (CUDA / MPS / CPU-slow) |
| `all <img> -o <out>` | Visible + invisible + metadata in one shot. | yes |
| `batch <dir> --mode all\|visible\|metadata [--auto]` | Whole directory; `--auto` reroutes per file. | depends on mode |

## Recipes

```bash
# 1. Just tell me what this image is
remove-ai-watermarks identify shot.png

# 2. Quick CPU clean for Gemini / Doubao / Jimeng / Samsung
remove-ai-watermarks visible in.png -o out.png
remove-ai-watermarks metadata out.png --remove

# 3. Full clean (needs GPU for the invisible step)
remove-ai-watermarks all in.png -o out.png

# 4. Erase an arbitrary logo at pixel box (x=1640, y=1930, w=400, h=100)
remove-ai-watermarks erase in.png --region 1640,1930,400,100 -o out.png

# 5. Whole directory, mixed sources
remove-ai-watermarks batch ./pics/ --mode all --auto
```

## Notes

- macOS GPU path uses MPS automatically; override with `--device cpu|mps|cuda`.
- `--restore-faces` (GFPGAN) needs Python < 3.13 and the `[restore]` extra.
- SSL error on first model download → `pip install certifi`; macOS may also
  need `/Applications/Python\ 3.*/Install\ Certificates.command`.
- No-setup web alternative: [raiw.cc](https://raiw.cc) (cloud GPU, paid for
  invisible removal).
- Lawful use only — some jurisdictions restrict removing an AI label as such.

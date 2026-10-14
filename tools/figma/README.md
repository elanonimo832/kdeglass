# Extracting values from a Figma kit

Tool that converts a Figma kit (`.fig`) into JSON with the design's **real values**:
radii, colors, alphas, text sizes. It is the step that fills
`tokens.toml` with data instead of impressions.

- Context: [../../DESIGN-REFERENCES.md](../../DESIGN-REFERENCES.md)
- Status: **the decoder is written and validated with a test `.fig`. It still needs
  to be tested against a real kit.**

## Result with the real export (Colors.zip)

`Colors.zip` (Figma Variables export) contains `Light.tokens.json` and
`Dark.tokens.json`: **61 color tokens in each mode, with exact hex and alpha**. They have been
converted to `tokens-color.toml` (61/61, lossless) with `tokens-from-figma.py`.

What it covers and what it does not:

| | |
|---|---|
| **Covers** | All colors, in light and dark: accents, fills, labels, grays and misc |
| **Does not cover** | Radii, text sizes, line height, spacings. **They are not variables in the kit**: they live in the node properties, so a Variables export cannot see them |

That is why the full `.fig` is still needed (`File → Save local copy`, only in the
desktop app).

## Verification status (honest)

| Part | Status |
|---|---|
| Locating the Kiwi payload inside the ZIP | **Verified** |
| Reading the container (version + chunk lengths) | **Verified** |
| Decompressing the schema (raw deflate and wrapped zlib) | **Verified** |
| Decoding the Kiwi schema | **Verified** |
| Decompressing the zstd data chunk (raw blocks) | **Verified** |
| Decoding the Kiwi document to JSON | **Verified** |
| Conversion of the Variables export to TOML | **Verified** with `Colors.zip`: 61/61 tokens |
| **Against a real `.fig`** | **IT WORKS**: `macOS 27 (Community).fig`, 80 MB, schema v106, 19.011 nodes, 168 MB of JSON |

The round-trip was validated by generating a `.fig` with a real Kiwi schema and real Kiwi
data, and checking that the values come back intact:

```
radii 10/6            -> recovered
alpha 0.85            -> 0.8500000238  (exact float32)
blue color (0, 0.568, 1) -> recovered
```

> Precision note: Kiwi's `float`s are 32-bit, so `0.85` is read as
> `0.8500000238418579`. It is correct, not an error. When generating `tokens.toml` you have to
> round it.

## Three traps that are hard to discover (all resolved)

Testing the decoder with a synthetic `.fig` **does not count**: you build the synthetic one
yourself and it ends up confirming your own assumptions. These three only appeared with the
real 80 MB file.

**1. The data chunk is already a complete zstd frame.** My initial version assumed
`[uint32 size][blocks]` and reinserted the magic number. In a real `.fig` the chunk
**starts** with the magic (`28 B5 2F FD`) and brings its own frame header, which varies:
in the real kit it is **13 bytes** (descriptor `0x80`, with a 4-byte content size and
window). Reinserting the magic corrupts everything.

**2. `fzstd` fails SILENTLY with large windows.** With the descriptor `0x80` it returned
14,7 MB of garbage **without throwing an error**, and the failure appeared much later, as
`Invalid type -8` from the Kiwi decoder. That is completely misleading: it looks like a schema
problem when it is a compression one. **The `zstd` CLI goes first**; `fzstd` only as a
last resort.

**3. The Kiwi version jump.** `kiwi-schema@0.4.7` **does not** understand Figma's v106 schema
(`Invalid type -8`). **`kiwi-schema@0.5.0` does**: 653 types defined. It is the
right package and it must be pinned.

And two minor traps: the schema goes in **raw deflate** (and `pako.inflate()` returns the
input buffer instead of failing, so you have to check the result, not trust that there is no
exception), and the document brings **BigInt**, which `JSON.stringify` does not know how to
serialize.

## How it is used

```bash
cd tools/figma
npm install                     # pako, kiwi-schema, fzstd
node decode-figma.js kit.fig kit.json
```

## Format it understands (and why the detail matters)

A `.fig` is a ZIP with a **self-describing Kiwi** binary payload:

```
[8]  "fig-kiwi"
[4]  version (uint32 LE)
[4]  schema chunk length (uint32 LE)
[N]  schema   -> RAW deflate (no header)
[4]  data chunk length (uint32 LE)
[M]  data     -> zstd WITHOUT frame header
```

**The detail that breaks any naive implementation:** the data chunk does not start
with the zstd magic number (`28 B5 2F FD`). They are **raw zstd blocks** preceded
by the uncompressed size in 4 little-endian bytes. To decompress it you have to
reinsert the magic in front of the blocks. Without that, zstd responds:

```
Decoding error (36): Unsupported frame parameter
```

**Second detail:** the schema goes in **raw** deflate, not wrapped zlib. It is
decompressed with `inflateRaw`. The tool tries both, because some versions
wrap the chunk with a zlib header.

**Third detail:** the decoder's name depends on the **schema's root type**.
It is not always called `decodeMessage`. The tool autodetects it among the
`decode*` ones that the compiled module exposes.

## Dependencies and why these

- **`kiwi-schema`** — decodes the schema and compiles the document. It is the real
  decoder; the rest is transport.
- **`pako`** — inflate/deflate for the chunks.
- **`kiwi-schema@0.5.0`** — minimum version. 0.4.7 does not understand Figma's v106 schema.
- **`fzstd`** — zstd in pure JS, only as a last resort (see trap 2).
- **`fig-kiwi` is discarded**: on npm only version **0.0.1** is published, which
  only understands clipboard paste (deflate) and does **not** read `.fig` from disk (zstd).
  Its README documents `readFigFile`, but that function does not exist in the published package.

## Legal notice

The Figma kit is **Apple material**. This tool extracts **numbers** and does not
redistribute assets. The `.fig`, the resulting JSON and the screenshots go **outside the
public repository**: see the `.gitignore` of this folder and §6 of
[../../ANALYSIS.md](../../ANALYSIS.md).

## Result on the real kit

```bash
node decode-figma.js "../../macOS 27 (Community).fig" ../../kit.json
# -> 168 MB of JSON, 19.011 nodes, 2.262 blobs

python3 extract-fig.py ../../kit.json ../../fig-extraido
# -> radii, squircle, effects, strokes, texts and spacings
```

It turned the 5 remaining gaps into `tokens/tokens-forma-efectos.toml`.

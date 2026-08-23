# Local AI Summarizer

An Android app for comparing on-device text summarization across three different
local inference runtimes on the same hardware, with the same passage and the same
instruction.

Everything runs locally. No cloud inference API is called by this app.

## Why

Plenty of demos show a language model running on a phone. Very few hold the input,
the instruction, and the device constant while swapping the runtime underneath, which
is the only way to see what each approach actually costs.

The three paths differ in more than speed:

| Path | Model choice | Runtime | Control |
| --- | --- | --- | --- |
| Gemini Nano | none — system-provided | AICore, managed by Google | temperature, top-K |
| MediaPipe | Google-published Gemma builds | flutter_gemma | temperature, top-K, session |
| GGUF | any compatible quantized model | llama.cpp | threads, context, sampling |

Managed, vendor-supported, and open — with the trade-offs that come with each.

## What it does

**Summarize** — pick one discovered model, paste a passage, choose a preset task
(2-sentence summary, key events, action items, or a custom instruction), and generate.
Latency, time to first token, estimated tokens, and throughput are shown for the run,
and the result can be saved.

**Benchmark** — run every discovered model against one standardized passage and
instruction, N times each (1, 3, or 5). Results are reported as the median across runs
with the min–max latency range, and each model's representative output is viewable.
Every individual run is written to history.

**History** — saved summaries and benchmark runs, searchable by text, model, or engine,
filterable by task type or by benchmark.

## Models

Gemini Nano is detected automatically when AICore reports the Prompt API as available.
The installed AICore version is recorded alongside results, so runs from different
devices or dates can be attributed to a specific build.

Other models are loaded from files placed in the app's external storage directory:

```
/Android/data/com.mycarejournals.local_ai_summarizer/files/models/
```

- `.task` / `.bin` → MediaPipe
- `.gguf` → llama.cpp

## Prompt formats

Instruction-tuned models expect their prompts wrapped in the framing they were trained
on. Sending a bare instruction to a model that expects one pushes it off-distribution,
so the format is resolved per model rather than assumed.

MediaPipe builds use the Gemma format. GGUF files are matched from the filename —
gemma, chatml (Qwen, Hermes), llama3, and mistral are recognized, and anything
unrecognized falls back to an unwrapped instruction, since a wrong wrapper is worse
than none. The resolved format is shown in the status line when a GGUF model loads.
Gemini Nano's Prompt API takes the instruction directly.

## Reading the measurements

Some things about the numbers this app produces are worth stating plainly:

- **Token counts are estimated as output characters ÷ 4.** They are not tokenizer
  output, and the three runtimes use different tokenizers. The displayed rate divides
  that estimate by total latency, including prompt processing and time to first token,
  so it is an end-to-end throughput proxy rather than pure decode speed.
- **Gemini Nano's Prompt API does not stream**, so time to first token cannot be
  measured for it. Total latency is shown in that column instead.
- **Models run in discovery order**, so a model benchmarked later runs on a warmer
  device than the first one did.
- **Output length is not normalized** across runtimes, and latency depends on it.
- **Nothing here evaluates output quality.** Speed says nothing about whether a summary
  is accurate or complete.

Repeat runs exist so that variance is visible rather than assumed. A single sample is
not evidence of stability.

## Building

```
flutter pub get
flutter run
```

Requires Android with `minSdk 26`. Gemini Nano requires a device with AICore support.
Release builds are signed with the debug key; this is a measurement tool, not a
distributed application.

## AI assistance

This project was designed and directed by Jason McArdle, who chose the questions it
asks, ran the tests on physical hardware, and owns the conclusions drawn from them.
Google Gemini 3.7 Flash assisted with implementation, API research, and troubleshooting.
All measurements come from a physical device, not from simulation.

## License

Apache License 2.0. Copyright 2026 Jason McArdle. See [LICENSE](LICENSE).

This is an independent project. It is not sponsored by, affiliated with, or endorsed
by Google.

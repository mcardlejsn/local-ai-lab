# Local AI Lab

An Android app for comparing on-device text summarization across local inference
runtimes on the same hardware, with the same passage and the same instruction.

Everything runs locally. No cloud inference API is called by this app.

## Why

Plenty of demos show a language model running on a phone. Very few hold the input,
the instruction, and the device constant while swapping the runtime underneath, which
is the only way to see what each approach actually costs.

The available paths differ in more than speed:

| Path | Model choice | Runtime | Control |
| --- | --- | --- | --- |
| Gemini Nano | none — system-provided | AICore, managed by Google | temperature, top-K, max output tokens |
| GGUF | any compatible quantized model | llama.cpp | threads, context, temperature, top-K, top-P, max output tokens |

Managed and open — with the trade-offs that come with each.

## What it does

**Summarize** — pick one discovered model, paste a passage, choose a preset task
(2-sentence summary, key events, action items, or a custom instruction), and generate.
Latency, time to first token, estimated tokens, and throughput are shown for the run,
and the result can be saved.

**Benchmark** — select any two or more discovered models, or select all, and run them
against one passage and instruction N times each (1, 3, or 5). Both fields are
editable, so the suite can be pointed at any text rather than only the sample it opens
with. Results are reported as the median across runs with the min–max latency range,
and each model's representative output is viewable. A completed suite can be saved as
a session.

**Saved sessions** — an archive of saved benchmark runs, with a detail view per session
and a comparison view that pairs two sessions model by model to show what moved between
them.

**History** — saved outputs, searchable by text, task, model name, or engine (for
example, nano or gguf), and filterable by task type.

## Models

Gemini Nano is detected automatically when AICore reports the Prompt API as available.
The installed AICore version is recorded alongside results, so runs from different
devices or dates can be attributed to a specific build.

Other models are loaded from files placed in the app's external storage directory:

```
/Android/data/com.mycarejournals.local_ai_summarizer/files/models/
```

- `.gguf` → llama.cpp

## Prompt formats

Instruction-tuned models expect their prompts wrapped in the framing they were trained
on. Sending a bare instruction to a model that expects one pushes it off-distribution,
so the format is resolved per model rather than assumed.

GGUF files are matched from the filename — Gemma, ChatML (Qwen, Hermes), Llama 3,
Mistral, and the other audited families are recognized. Anything unrecognized falls
back to an unwrapped instruction, since a wrong wrapper is worse than none. The
resolved format is shown in the status line when a GGUF model loads. Gemini Nano's
Prompt API takes the instruction directly.

## Recall

Benchmark runs are scored for coverage: how much of the source passage's substance
survived into the output.

The passage is reduced to a set of content tokens — lowercased, split, stripped of
stopwords. Anything containing a digit is kept whole, so `4.2.1`, `09:15`, `12%` and
`940` each stay a single token. The model's output is then checked for each one. Word
tokens match from a stem, so `restarted` credits `restart`. Digit tokens must match
exactly and at a boundary, so `12%` is never credited by `12:00` and `940` is never
credited by `9400`.

The score is the count found out of the count derived, and the total therefore varies
with the passage. Each saved run stores its own total, and the comparison screen will
not print a delta between two sessions whose totals differ.

Two things this does and does not tell you:

- It is deterministic and has no model in the loop. The same output against the same
  passage always produces the same score, on any device, with nothing to configure.
- It measures coverage, not correctness. A model that reproduces the passage verbatim
  scores full marks, and a fluent summary that drops a number scores below one that
  keeps the number and reads badly. The manual 1–5 accuracy score on saved sessions
  exists for the judgment recall cannot make.

## Reading the measurements

Some things about the numbers this app produces are worth stating plainly:

- **Token counts are estimated as output characters ÷ 4.** They are not tokenizer
  output, and the models can use different tokenizers. The displayed rate divides that
  estimate by total latency, including prompt processing and time to first token, so it
  is an end-to-end throughput proxy rather than pure decode speed.
- **Gemini Nano's Prompt API does not stream**, so time to first token cannot be
  measured for it. Total latency is shown in that column instead.
- **Models run in discovery order**, so a model benchmarked later runs on a warmer
  device than the first one did.
- **Output length is not normalized** across runtimes, and latency depends on it.
- **Recall measures coverage, not accuracy.** See above. Speed says nothing about
  either.

Repeat runs exist so that variance is visible rather than assumed. A single sample is
not evidence of stability.

## Building

```
flutter pub get
flutter run
```

Requires Android with `minSdk 26`. Gemini Nano requires a device with AICore support.
Release builds are signed with a keystore configured in `key.properties`, which is not
committed; without it, the release signing config resolves to nothing and only debug
builds will run.

## AI assistance

This project was designed and directed by Jason McArdle, who chose the questions it
asks, ran the tests on physical hardware, and owns the conclusions drawn from them.
Google Gemini 3.7 Flash assisted with implementation, API research, and troubleshooting.
All measurements come from a physical device, not from simulation.

## License

Apache License 2.0. Copyright 2026 Jason McArdle. See [LICENSE](LICENSE).

This is an independent project. It is not sponsored by, affiliated with, or endorsed
by Google.

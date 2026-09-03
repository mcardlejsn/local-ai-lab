# Local AI Lab

An Android app for running and comparing on-device language models on the same
hardware with controlled passages, instructions, and measurements.

Inference runs locally. Local AI Lab does not call a cloud inference API.
Network access occurs only when the user explicitly discovers or downloads a
model or opens external model and license information.

## Why

Plenty of demos show a language model running on a phone. Very few hold the
input, instruction, and device constant while changing the model and runtime.
Local AI Lab makes those trade-offs visible without presenting one result as a
universal ranking.

## Runtime paths

| Path | Model choice | Runtime | Control |
| --- | --- | --- | --- |
| Gemini Nano | System-provided | Android AICore through ML Kit GenAI Prompt API `1.0.0-beta4` | Temperature, top-K, max output tokens |
| GGUF | Compatible local `.gguf` files | llama.cpp through `llama_flutter_android 0.2.6` | Threads, context, temperature, top-K, top-P, seed, max output tokens |
| LiteRT-LM | Exact approved `.litertlm` artifacts | `flutter_gemma_litertlm 1.5.3`, bundling LiteRT-LM `0.16.0` | GPU backend; max output tokens; effective sampling fixed by the current runtime |

## What it does

**Run** — select an installed model, paste a passage, choose Two-Sentence
Summary, Key Events, Action Items, or Custom, and generate output. The result
can be saved with its task, model identity, latency, estimated token count,
estimated rate, and measurable TTFT.

**Compare** — run one controlled test across two or more installed models, or
send the current Run task and passage into Compare. Each model can run 1, 3, or
5 times. Successful runs are summarized with medians, latency retains its
minimum-to-maximum range, and individual outputs remain available.

**Models** — manage Candidates, Installed models, and device-specific
Recommended results. Candidate discovery and downloads occur only after an
explicit user action.

**Results** — review saved Runs and Compare sessions, inspect individual
outputs, apply the manual 0–5 review score, and compare two saved sessions.

## Models and Candidates

Gemini Nano is detected when AICore reports the Prompt API as available. Local
AI Lab requests the base-model name through the supported runtime API and
records the returned identifier exactly when available. It also records the
AICore service version separately. Neither value is inferred from the phone,
Android build, feature availability, performance, marketing name, or release
date.

The following are distinct pieces of information:

- **Base model** — the value returned by `GenerativeModel.getBaseModelName()`.
- **AICore service** — the installed Android service package version serving
  Gemini Nano; it is not the model identity.
- **Prompt API** — the ML Kit library version used by the app.
- **Availability** — whether the Prompt API is usable on the current device.
- **Device platform** — the Android platform/build on which the result ran.

File-backed models live in:

```text
/Android/data/com.mycarejournals.local_ai_summarizer/files/models/
```

- `.gguf` files run through llama.cpp.
- Approved `.litertlm` files run through LiteRT-LM on the GPU backend.

The curated LiteRT-LM catalog contains two exact runtime-qualified artifacts:

- Qwen3 0.6B
- OLMo 2 1B Instruct

Each catalog entry is pinned to an immutable repository revision and records
its exact filename, byte size, SHA-256 hash, license, artifact context, runtime
profile, and thinking behavior. Qualification confirms compatibility and clean
operation with the pinned runtime; it does not establish quality, safety, or
performance on every phone.

GGUF Discovery searches bounded Hugging Face results and applies the app's
mechanical compatibility policy. Candidates must be public and ungated,
instruction- or chat-suitable, a single unsharded Q4_K_M file no larger than
3 GB, from a supported prompt/runtime family, with resolvable license
information and an available SHA-256 hash. Candidate status is not a quality
or safety endorsement.

## Prompt formats

Instruction-tuned models expect the framing used during training. GGUF prompt
formats are resolved per recognized model family rather than applied
universally. Unrecognized files fall back to an unwrapped instruction because
an incorrect wrapper can be worse than none. Gemini Nano receives the
instruction through the Prompt API. LiteRT-LM uses the chat template embedded
for its approved artifact profile.

## Recall

Compare runs are scored for coverage: how much of the source passage's expected
content survived into the output.

The passage is reduced to content tokens. Word tokens use conservative stem
matching. Tokens containing digits, such as `4.2.1`, `09:15`, `12%`, and `940`,
must match exactly at a boundary. Each saved run retains its own found and total
counts.

Recall is deterministic and contains no scoring model, but it measures coverage
rather than correctness. A verbatim output can receive full recall, while a
fluent output that drops one number can score lower. The manual 0–5 review score
exists for judgments this mechanical check cannot make.

## Reading the measurements

- **Token counts are estimated as output characters divided by four.** They are
  not tokenizer output, and different models can use different tokenizers.
- **Rate is an estimated end-to-end proxy.** It divides the estimated output
  token count by total latency, including prompt processing and TTFT where
  observable. It is not pure decode speed.
- **Gemini Nano is non-streaming in the current integration.** The API returns a
  completed response, so first-token arrival cannot be measured separately.
  Nano displays `TTFT --` and is excluded from TTFT comparisons and
  recommendations. Total latency remains available.
- **Models run sequentially.** A model tested later can run on a warmer device.
- **Output length is not normalized** across runtimes, and latency depends on
  it.
- **Recall is not accuracy.** Speed establishes neither coverage nor factual
  correctness.

Generated output can omit, alter, or invent details. Human review of the source
and output remains necessary. One task, device, or session does not establish
general model quality or future performance.

## Privacy and local storage

Passages, prompts, generated output, comparison data, and saved results are
stored locally. Local AI Lab does not transmit them and does not use accounts,
analytics, cloud inference, or Android backup. Model discovery, model downloads,
and external information links are the app's explicit network-related actions.

## Historical report

[Local AI Lab Five-Run Benchmark Report](Local_AI_Lab_Five_Run_Benchmark_Report.pdf)
records an August 23, 2026 physical-device test of an earlier app version. It
includes the former MediaPipe path and the TTFT presentation used at that time;
it is preserved as a dated historical result rather than current 1.0 behavior.

## Building

```text
flutter pub get
flutter run
```

Requires Android with `minSdk 26`. Gemini Nano additionally requires a device
with supported AICore Prompt API availability. Release builds use a keystore
configured in the uncommitted `key.properties` file.

## AI assistance

This project was designed and directed by Jason McArdle, who chose the product
and testing decisions, ran the tests on physical hardware, reviewed the output,
and owns the published conclusions. Google Gemini 3.7 Flash assisted with
implementation, API research, and troubleshooting. ChatGPT assisted with later
application refinement, methodology, persistence, data interpretation, and
release review. Reported measurements come from physical devices rather than
simulation.

## License

Apache License 2.0. Copyright 2026 Jason McArdle. See [LICENSE](LICENSE).

This is an independent project. It is not sponsored by, affiliated with, or
endorsed by Google.

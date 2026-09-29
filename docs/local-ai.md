# Island and local intelligence

## Implemented

- A hidden-at-launch, top-centered island with an animated mask expanding from physical notch bounds, notchless fallback, built-in/active/selected display choice, preserved drafts, menu-bar recovery and scoped Command-Shift-Enter registration. Reduced motion skips the spring. Categorized navigation and appearance settings live in the top-left dropdown. Existing pet, organization, games, settings and capture share the original controller.
- `InferenceProvider` isolates app code from runtime-specific requests. `OllamaProvider` uses loopback-only ephemeral requests, rejects redirects and remote-model metadata, checks completion capability, parses bounded streaming responses, and supports cancellation, timeouts and unload.
- `ManagedLocalProvider` launches one pinned llama.cpp process per request with bounded pipe I/O, no shell evaluation, no listening socket, a 180-second deadline, cancellation, and forced termination fallback. Its process ends after generation. Text chat uses the pinned model's ChatML format.
- The packaged runtime includes Apple silicon and Intel binaries from llama.cpp b11236. `prepare-runtime.sh` checks release-asset SHA-256 hashes before extracting. The app remains universal; the workers require macOS 13.3. Runtime MIT and model Apache 2.0 notices are included.
- Model setup downloads Qwen2.5 0.5B Instruct Q4_K_M at repository revision `9217f5db79a29953eb74d5343926648285ec7e67`. Expected size: 491,400,032 bytes. SHA-256: `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`. Existing weights remain until a new download passes integrity checks. Download progress, cancel, server-supported resume, retry, compatibility checks and removal are exposed. A fresh download automatically runs a short readiness request with no personal data. The compact model is not a strong general reasoning model.
- Chat uses explicit text/file/clipboard handoff and opt-in approved project memory. It does not persist transcripts or attached document contents automatically. Search enumerates at most 2,000 entries and returns at most 40 matches, ignoring hidden/package/dependency content and symlink escapes. Optional content search reads at most 2 MB, with a 64 KB per-file limit, and shows source excerpts without sending them to AI automatically.
- Natural-language action interpretation generates one validated proposal for task creation, note saving or focus. Project opening uses an explicit project picker. Every mutation requires a visible review. Generated documents are never treated as authorization.
- Durable jobs prevent interrupted actions from replaying. Up to 100 pending reviews are kept without silent eviction; completed history is capped at 100 records and 30 days, with a separate forget control. Ritual steps and their consumed schedule are persisted atomically. Tasks and notes have stable IDs and unchanged-record undo. File moves record each step before mutation, revalidate hashes and destinations, never overwrite, and stop undo when intervening edits are detected. Interrupted rows require manual inspection instead of automatic retry. Plans are limited to 30 regular files of at most 100 MB each.
- Workspace rituals support manual or one-time scheduled review, a master pause and deletion. They prepare reviewed folder/focus actions; they do not perform unattended external actions. Meeting and daily wrap-up buttons prepare a visible attachment from explicitly requested local records.

## Verification performed

The core suite covers remote-model rejection, unsupported capabilities, stream error handling, invalid proposals, interrupted jobs, offset-display geometry, model integrity failures, move/undo persistence, stale file previews, collisions, journal-write failure and symbolic-link rejection, in addition to the companion tests.

Live integration tests exercise installed local Ollama and the managed worker on the development Apple silicon Mac. The packaged app readiness check also produced text under a process sandbox that denied all networking, without contacting Ollama. Release binaries were built for arm64 and x86_64 and the app's ad-hoc signature verified. A fresh model-storage test exercised the packaged installer, download, hash verification, automatic readiness request and cleanup without using an existing model cache. These checks do not establish Intel performance or a clean Mac/user environment.

```sh
MOLT_TEST_OLLAMA=1 swift test
MOLT_TEST_RUNTIME="$PWD/dist/Runtime/arm64/llama-completion" \
MOLT_TEST_MODEL="$PWD/dist/qwen2.5-0.5b-instruct-q4_k_m.gguf" swift test
./dist/Molt.app/Contents/MacOS/Molt --verify-local-ai /path/to/verified-model.gguf
# Downloads into isolated temporary storage, verifies readiness, then removes it:
./dist/Molt.app/Contents/MacOS/Molt --verify-model-install
```

## Remaining qualification and scope

Do not advertise the ordinary-user AI release as fully qualified until a clean Mac setup, Intel hardware, minimum supported OS, low-memory/disk conditions, model download interruption, accessibility and physical multi-display tests pass. No traffic-capture or eight-hour hardware measurements have been completed in this change.

There is one curated managed model, not a benchmarked model catalog or arbitrary GGUF importer. Hardware checks are conservative thresholds, not measured performance promises. AI files use a separate versioned JSON store; legacy records are backed up before version adoption, future versions are rejected, and corrupt data is preserved with write operations disabled. A richer recovery UI remains work. Search is bounded filename and opt-in text search, not a persistent full-text index.

Screen help now offers permission-gated one-shot capture on macOS 14+ and screenshot attachment on macOS 13+. A preview must be explicitly attached; images require an Ollama model advertising vision, while Vision OCR supplies text to the managed model. No screen capture or live vision inference was exercised against the user’s desktop during automated verification. Molting offers explicit web search in an ephemeral browser plus robots-aware, bounded public HTTPS text extraction. Sources are untrusted context and never action authorization.

Accessibility control, arbitrary shell execution, automatic messaging, general browser context, recurring/app-lifecycle automation triggers and unrestricted agent loops are deliberately not exposed. The roadmap gates those on separate scope/recovery tests. Later creature artwork and game catalog additions retain their existing boundaries in `release-scope.md`.

## Sources

- [Ollama chat API](https://docs.ollama.com/api/chat)
- [Ollama model listing](https://docs.ollama.com/api/tags)
- [Pinned llama.cpp release](https://github.com/ggml-org/llama.cpp/releases/tag/b11236)
- [Qwen model source and license](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/tree/9217f5db79a29953eb74d5343926648285ec7e67)

# prp-yc-demo

Join Pramod's prima.cpp Qwen2.5-7B inference ring from a Mac
as a worker rank. One command installs the Homebrew
dependencies, clones and builds
[p13i/prima.cpp-yc-hackathon](https://github.com/p13i/prima.cpp-yc-hackathon)
into `./prima.cpp`, downloads the model, verifies its sha256,
and starts `llama-cli` as your rank.

```sh
git clone https://github.com/p13i/prp-yc-demo && cd prp-yc-demo && make mac-join
```

| Variable    | Default          | Meaning                                      |
| ----------- | ---------------- | -------------------------------------------- |
| `MASTER`    | `172.17.23.252`  | Rank 0 IP (Tailscale: `100.78.165.127`)      |
| `RANK`      | `1`              | Your rank in the ring                        |
| `WORLD`     | `2`              | Total number of ranks                        |
| `NEXT`      | `$(MASTER)`      | IP of rank `RANK+1` (rank 0 if you are last) |
| `NGL`       | `14`             | Layers to run on Metal (`-ngl`)              |
| `MODEL_DIR` | `$(HOME)/models` | Where the GGUF is stored                     |

Override on the command line, for example
`make mac-join RANK=2 WORLD=3 NEXT=172.17.23.252`.

Requirements: Apple silicon Mac, Homebrew, and either the same
Wi-Fi as the master or Tailscale.

Downloads: the 4.7 GB `Qwen2.5-7B-Instruct-Q4_K_M.gguf`, from
the master's file server at `http://<MASTER>:8090/` first and
from Hugging Face if that is unreachable, verified against
sha256 `65b8fcd92af6b4fefa935c625d1ac27ea29dcb6ee14589c55a8f115ceaaa1423`.

What you should see: `starting llama-cli worker rank N`
followed by the exact `llama-cli` line. Leave the terminal
open; the ring is served by the master at
`http://<MASTER>:8088/v1` (OpenAI-compatible, model id
`qwen2.5-7b`).

Other targets: `make deps`, `make build`, `make model`,
`make join`, `make clean`.

## Demo QM and GBrain on the ring

Two applications run against the ring with no cloud API
keys, from this repo, on any Mac that can reach the master.
Both use the master's OpenAI-compatible endpoint
`http://<MASTER>:8088/v1` (model id `qwen2.5-7b`, any API
key). Override `MASTER` the same way as above.

```sh
make demo-gbrain            # needs bun: brew install oven-sh/bun/bun
make demo-qm                # needs node >= 22; leaves the QM core running on :8085
make demo-qm-web            # optional: QM web UI on http://<MASTER>:8096 for phones
make demo-qm-stop           # kill the QM core
```

`make demo-gbrain` clones
[p13i/gbrain-yc-hackathon](https://github.com/p13i/gbrain-yc-hackathon)
into `./gbrain`, runs `bun install`, creates a keyless PGLite
brain in `./gbrain-home` (`init --pglite --no-embedding --git`),
imports the three notes in `./sample-notes/`, sets
`models.chat`, `models.think` and `models.expansion` to
`llama-server:qwen2.5-7b`, and runs `gbrain think` on
`QUESTION` (default: "Which machines form the prima.cpp ring
and what does each one run?"; override with
`make demo-gbrain QUESTION="..."`). Expected output ends with
a Markdown answer citing the notes, then a footer like:

```text
Model: llama-server:qwen2.5-7b | Pages: 3 | Takes: 0 | Graph: 0 | Citations: 1
Warnings: QUESTION_EMBED_FAILED, ...
```

`QUESTION_EMBED_FAILED` is expected: the brain has no
embeddings and retrieval is keyword-only. A think prompt is
about 3.4k tokens, so the master must run `llama-server` with
`-c 16384` (8192 per slot); at `-c 4096` gbrain reports
`SYNTHESIS_EMPTY_ANSWER`. Only one process may open the
PGLite file at a time: stop a `gbrain serve` on this brain
before running `think` again.

`make demo-qm` clones
[p13i/qm-yc-hackathon](https://github.com/p13i/qm-yc-hackathon)
into `./qm`, runs `npm install`, writes `./qm/.env` from
`scripts/qm.env.template` (secrets from
`openssl rand -hex 32`, `MASTER` substituted, `HARNESS=pi`,
`MODEL_PROVIDER=openrouter` pointed at the master, in-memory
stores, `ALLOW_UNAUTHENTICATED_CORE=1`), starts the core in
the background (pidfile `./qm/qm-core.pid`, log
`./qm/qm-core.log`), waits for
`[qm] listening on :8085 (org=acme, store=memory, ...)`, and
POSTs one turn:

```sh
curl -s http://127.0.0.1:8085/v1/turns -H 'content-type: application/json' \
  -d '{"surface":"battery","actor":{"externalId":"U1"},"conversation":{"kind":"dm","threadRef":"demo1"},"text":"Reply with one word: mesh"}'
```

Expected output:

```json
{
  "reply": "mesh",
  "sessionId": "c704ccd0-...",
  "status": "ok"
}
```

A QM turn through the WAN ring can take 1 to 3 minutes: the
Pi harness prompt is about 2.9k tokens. The core keeps
running after the script exits so more turns can be sent;
`make demo-qm-stop` kills it. A rerun while the core is up
reuses it.

`make demo-qm-web` runs `plugins/web-ui` in the foreground on
`:8096` against that core. Sign-in is a cookie set by
`POST /signin {"user":"<id>"}` with no loopback check, so a
phone on the same network can use `http://<MASTER>:8096`.

`make proxy` runs `scripts/compat_proxy.py` on `:8088` in
front of a `llama-server` on `:8080`, which is how the master
serves the endpoint above: it strips `tools`, `tool_choice`
and `response_format` (which the prima.cpp server rejects
with a 500) and serves the model as `qwen2.5-7b`. Run it on
a master built from this repo.

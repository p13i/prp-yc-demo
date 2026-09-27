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

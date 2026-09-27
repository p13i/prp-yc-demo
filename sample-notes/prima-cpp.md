# prima.cpp

prima.cpp is a fork of llama.cpp that runs one model across
several machines. Each machine is a rank; the ranks pass
activations around a ring, so every generated token is
computed by all of them together.

The build used here is
https://github.com/p13i/prima.cpp-yc-hackathon. Rank 0 is
the master and runs `llama-server`; the other ranks run
`llama-cli` as workers. A Mac joins as a worker with
`make mac-join` from the prp-yc-demo repository.

The server in this fork exposes only `/v1/models` and
`/v1/chat/completions`, and it rejects requests that carry
`tools` or `tool_choice` with a 500. The compat proxy in
`scripts/compat_proxy.py` strips those fields so clients
such as QM and GBrain work unchanged.

# The ring

The demo ring serves Qwen2.5-7B-Instruct (Q4_K_M GGUF,
4.7 GB) across two machines:

- rank 0: a MacBook Air M4 on Metal, 20 layers, the
  master, LAN address 172.17.23.252 and Tailscale address
  100.78.165.127
- rank 1: a WSL box with an RTX 4060 Ti on CUDA, 8 layers

The master runs `llama-server` on port 8080 with a 16384
token context (8192 per slot, two slots). In front of it
the compat proxy on port 8088 serves an OpenAI-compatible
API at `http://<MASTER>:8088/v1` with the model id
`qwen2.5-7b`; any API key is accepted.

Measured on the two-rank ring: about 5.7 tokens per second
of generation and about 34 tokens per second of prompt
processing.

# This demo

Two applications run on the ring with no cloud API keys:

- QM (https://github.com/p13i/qm-yc-hackathon) with
  `HARNESS=pi`, routed through its OpenRouter provider to
  the ring master's compat proxy. One turn is a POST to
  `/v1/turns` on the QM core and can take one to three
  minutes over the WAN ring, because the harness prompt is
  about 2900 tokens.
- GBrain (https://github.com/p13i/gbrain-yc-hackathon)
  with a PGLite brain, no embeddings, and `models.chat`,
  `models.think` and `models.expansion` set to
  `llama-server:qwen2.5-7b`. `gbrain think` sends a prompt
  of about 3400 tokens, which is why the master needs the
  16384 token context.

`make demo-gbrain` and `make demo-qm` in prp-yc-demo run
each one end to end against `MASTER`.

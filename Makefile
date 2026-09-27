# Join Pramod's prima.cpp Qwen ring from a Mac as a worker rank.
#
#   make mac-join
#   make mac-join RANK=2 WORLD=3 NEXT=172.17.23.252

MASTER ?= 172.17.23.252
RANK ?= 1
WORLD ?= 2
NEXT ?= $(MASTER)
NGL ?= 14
MODEL_DIR ?= $(HOME)/models

JOIN = bash scripts/join.sh --rank $(RANK) --world $(WORLD) --master $(MASTER) --next $(NEXT) --ngl $(NGL) --model-dir $(MODEL_DIR)

.PHONY: mac-join deps build model join clean

mac-join:
	$(JOIN) --only all

deps:
	$(JOIN) --only deps

build:
	$(JOIN) --only build

model:
	$(JOIN) --only model

join:
	$(JOIN) --only join

clean:
	rm -rf prima.cpp

# Demo QM and GBrain against the ring master at $(MASTER):8088.
#
#   make demo-gbrain
#   make demo-qm && make demo-qm-stop
#   make proxy            (on the master, in front of llama-server :8080)

QUESTION ?= Which machines form the prima.cpp ring and what does each one run?

.PHONY: demo-gbrain demo-qm demo-qm-web demo-qm-stop proxy

demo-gbrain:
	MASTER=$(MASTER) QUESTION='$(QUESTION)' bash scripts/demo_gbrain.sh

demo-qm:
	MASTER=$(MASTER) bash scripts/demo_qm.sh

demo-qm-web:
	MASTER=$(MASTER) bash scripts/demo_qm_web.sh

demo-qm-stop:
	bash scripts/demo_qm.sh --stop

proxy:
	python3 scripts/compat_proxy.py --listen 0.0.0.0:8088 --upstream http://127.0.0.1:8080 --alias qwen2.5-7b

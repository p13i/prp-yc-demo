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

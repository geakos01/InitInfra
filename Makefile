.DEFAULT_GOAL := help
PLAYBOOK := site.yml
ANSIBLE  := ansible-playbook -i localhost, -c local

.PHONY: help dev check diff lint verify

help:  ## Ezt a listat mutatja
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  [36m%-10s[0m %s
", $$1, $$2}'

dev:  ## A playbook futtatasa helyben (ez a fo parancs)
	$(ANSIBLE) $(PLAYBOOK)

check:  ## Szarazon futtatas - nem valtoztat semmit
	$(ANSIBLE) --check --diff $(PLAYBOOK)

diff:  ## Csak a valtozasokat mutatja
	$(ANSIBLE) --diff $(PLAYBOOK)

lint:  ## Szintaxis-ellenorzes futtatas nelkul
	$(ANSIBLE) --syntax-check $(PLAYBOOK)

# Az idempotencia a projekt egyik alapkovetelmenye: a MASODIK futasnak csupa
# "ok"-ot kell irnia. Ha "changed"-et ir, ott valami minden korben ujra dolgozik.
idempotens:  ## Ketszer lefuttatja, es hibat jelez ha a masodik valtoztat
	@$(ANSIBLE) $(PLAYBOOK) > /dev/null
	@echo "--- masodik futas ---"
	@$(ANSIBLE) $(PLAYBOOK) | tee /tmp/masodik.log | tail -5
	@if grep -qE 'changed=[1-9]' /tmp/masodik.log; then 		echo ""; echo "NEM IDEMPOTENS: a masodik futas is valtoztatott."; 		grep -E 'changed=[1-9]' /tmp/masodik.log; exit 1; 	else 		echo ""; echo "IDEMPOTENS: a masodik futas nem valtoztatott semmit."; 	fi

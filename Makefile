.DEFAULT_GOAL := help
PLAYBOOK := site.yml
ANSIBLE  := ansible-playbook -i localhost, -c local

.PHONY: help dev verify check diff lint idempotens

help:  ## Ezt a listat mutatja
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed -e 's/:.*## /|/' | column -t -s '|'

dev:  ## A playbook futtatasa helyben (ez a fo parancs)
	$(ANSIBLE) $(PLAYBOOK)

verify:  ## Ellenorzi, hogy a gep keszen all-e (nem valtoztat semmit)
	$(ANSIBLE) --tags verify $(PLAYBOOK)

check:  ## Mit valtoztatna? Csak MAR TELEPITETT gepen ertelmes
	$(ANSIBLE) --check --diff $(PLAYBOOK)

diff:  ## Csak a valtozasokat mutatja
	$(ANSIBLE) --diff $(PLAYBOOK)

lint:  ## Szintaxis-ellenorzes futtatas nelkul
	$(ANSIBLE) --syntax-check $(PLAYBOOK)

# Az idempotencia alapkovetelmeny: a MASODIK futasnak csupa 'ok'-ot kell irnia.
# Ha 'changed'-et ir, ott valami minden korben ujra dolgozik.
idempotens:  ## Ketszer futtat, es hibat jelez ha a masodik valtoztat
	@$(ANSIBLE) $(PLAYBOOK) > /tmp/elso.log 2>&1 || (tail -20 /tmp/elso.log; exit 1)
	@echo '--- masodik futas ---'
	@$(ANSIBLE) $(PLAYBOOK) > /tmp/masodik.log 2>&1 || (tail -20 /tmp/masodik.log; exit 1)
	@tail -3 /tmp/masodik.log
	@grep -qE 'changed=[1-9]' /tmp/masodik.log && (echo; echo 'NEM IDEMPOTENS:'; grep -E 'changed=[1-9]' /tmp/masodik.log; exit 1) || (echo; echo 'IDEMPOTENS: a masodik futas nem valtoztatott.')

PATCH         = applyHarness.patch
CONTRACTS_DIR = ../src
MUNGED_DIR    = munged

help:
	@echo "usage:"
	@echo "  make clean:  remove all generated files (those ignored by git)"
	@echo "  make $(MUNGED_DIR): create $(MUNGED_DIR) directory by applying the patch file to $(CONTRACTS_DIR)"
	@echo "  make record: record a new patch file capturing the differences between $(CONTRACTS_DIR) and $(MUNGED_DIR)"

munged:  $(wildcard $(CONTRACTS_DIR)/*.sol) $(PATCH)
	rm -rf $(MUNGED_DIR)
	cp -r $(CONTRACTS_DIR) $@
	patch -p0 -d $@ < $(PATCH)

record:
	diff -ruN $(CONTRACTS_DIR) $(MUNGED_DIR) | sed 's+\.\./src/++g' | sed 's+munged/++g' > $(PATCH)

munged-rewards: $(wildcard $(CONTRACTS_DIR)/*.sol) applyHarnessRewards.patch
	rm -rf munged-rewards
	cp -r $(CONTRACTS_DIR) $@
	patch -p0 -d $@ < applyHarnessRewards.patch

record-rewards:
	diff -ruN $(CONTRACTS_DIR) munged-rewards | sed 's+\.\./src/++g' | sed 's+munged-rewards/++g' > applyHarnessRewards.patch

clean:
	git clean -fdX
	touch $(PATCH)

.PHONY: help record clean

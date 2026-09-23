all: install

SRCS := Cargo.toml Cargo.lock src/main.rs

NATIVE_PATH=target/release/apk-info-extractor
$(NATIVE_PATH): $(SRCS)
	@cargo build --release

test: $(NATIVE_PATH)
	@for FILE in test/*.xml; do \
		echo "[$${FILE}] $$($(NATIVE_PATH) --print-app-id $${FILE})/$$($(NATIVE_PATH) --verbose --print-activity-name $${FILE})"; \
	done

test-verbose: $(NATIVE_PATH)
	@for FILE in test/*.xml; do \
		echo "[$${FILE}]"; \
		$(NATIVE_PATH) --verbose --print-app-id $${FILE}; \
		$(NATIVE_PATH) --verbose --print-activity-name $${FILE}; \
		echo; \
	done

benchmark: $(NATIVE_PATH)
	hyperfine '$(NATIVE_PATH) --print-app-id test/WalkaboutMiniGolf.xml'

# The extractor runs on the host that runs `lepton`, so it is built for the
# host architecture unless a cross target is requested explicitly.
# LEPTON_TARGET_ARCH=aarch64 reproduces the original Steam Frame cross build.
LEPTON_TARGET_ARCH ?= $(shell uname -m)

ifeq ($(LEPTON_TARGET_ARCH),aarch64)
CARGO_TRIPLE := aarch64-unknown-linux-gnu
CARGO_LINKER_ENV := CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
else
CARGO_TRIPLE := x86_64-unknown-linux-gnu
CARGO_LINKER_ENV :=
endif

TARGET_PATH=target/$(CARGO_TRIPLE)/release/apk-info-extractor
$(TARGET_PATH): $(SRCS)
	@$(CARGO_LINKER_ENV) \
	cargo build --target=$(CARGO_TRIPLE) --profile=release

bin:
	mkdir -p $@
bin/apk-info-extractor: $(TARGET_PATH) | bin
	@install -Dm755 -v $< $@
install: bin/apk-info-extractor

clean:
	cargo clean
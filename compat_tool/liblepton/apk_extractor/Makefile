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

TARGET_PATH=target/aarch64-unknown-linux-gnu/release/apk-info-extractor
$(TARGET_PATH): $(SRCS)
	@CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
	cargo build --target=aarch64-unknown-linux-gnu --profile=release

bin:
	mkdir -p $@
bin/apk-info-extractor: $(TARGET_PATH) | bin
	@install -Dm755 -v $< $@
install: bin/apk-info-extractor

clean:
	cargo clean
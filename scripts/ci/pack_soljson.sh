#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(realpath "$(dirname "$0")")"
SOLJSON_JS="$1"
SOLJSON_WASM="$2"
SOLJSON_WASM_SIZE=$(wc -c "${SOLJSON_WASM}" | cut -d ' ' -f 1)
OUTPUT="$3"

(( $# == 3 )) || { >&2 echo "Usage: $0 soljson.js soljson.wasm packed_soljson.js"; exit 1; }

# If this changes in an emscripten update, it's probably nothing to worry about,
# but we should double-check when it happens and adjust the tail command below.
[ "$(head -c 5 "${SOLJSON_JS}")" == "null;" ] || { >&2 echo 'Expected soljson.js to start with "null;"'; exit 1; }

echo "Packing $SOLJSON_JS and $SOLJSON_WASM to $OUTPUT."
(
	echo -n 'var Module = Module || {}; Module["wasmBinary"] = '
	echo -n '(function(source, uncompressedSize) {'
	# Note that base64DecToArr assumes no trailing equals signs.
	cat "${SCRIPT_DIR}/base64DecToArr.js"
	# Note that mini-lz4.js assumes no file header and no frame crc checksums.
	cat "${SCRIPT_DIR}/mini-lz4.js"
	echo -n 'return uncompress(base64DecToArr(source), uncompressedSize);})'
	echo -n '("'
	# We fix lz4 format settings, remove the 8 bytes file header and remove the trailing equals signs of the base64 encoding.
	lz4c --no-frame-crc --best --favor-decSpeed "${SOLJSON_WASM}" - | tail -c +8 | base64 -w 0 | sed 's/[^A-Za-z0-9\+\/]//g'
	echo -n "\",${SOLJSON_WASM_SIZE});"
	# Remove "null;" from the js wrapper.
	tail -c +6 "${SOLJSON_JS}"
) > "$OUTPUT"

echo "Testing $OUTPUT."

node <<EOF
var embeddedBinary = require('./upload/soljson.js').wasmBinary
require('fs').readFile("$SOLJSON_WASM", function(err, data) {
	if (err) throw err;
	if (data.length != embeddedBinary.length)
		throw "different size";
	for(var i = 0; i < data.length; ++i)
		if (data[i] != embeddedBinary[i])
			throw "different contents";
	console.log("Binaries match.")
})
EOF

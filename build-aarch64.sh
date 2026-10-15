#!/usr/bin/env bash
set -e

# Build script for aarch64 GNU/Linux (glibc 2.17+ compatible)
# Produces:
# 1) lpac-aarch64-nopcsc (standalone single binary without pcsc)
# 2) lpac-aarch64-pcsc-suite.tar.gz (lpac + libpcsclite.so.1 + pcscd + pcsc_scan)

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="/tmp/build-aarch64-env"
mkdir -p "${TMP}"

# Build script for aarch64 glibc (compatible with glibc 2.17+)
# Produces:
# 1) lpac: Single binary (236KB) containing pcsc, at, at_csim, curl, stdio
#    (statically links libpcsclite.a so NO .so files are needed!)
# 2) pcscd: PC/SC daemon (555KB)
# 3) pcsc_scan: PC/SC card & reader scanner (145KB)
# 4) libpcsclite.so.1: Standalone shared library (not required by lpac)

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Artifacts are ready in ${WORKDIR}/lpac and ${WORKDIR}/lpac-aarch64.tar.gz"

#!/bin/bash
source "$(dirname "$0")/common.sh"
swift format lint --strict --recursive Sources Tests Package.swift
python3 -m compileall -q sidecar scripts/configure_runtime.py
python3 scripts/audit_repository.py

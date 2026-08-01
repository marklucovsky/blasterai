// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SerialTests.swift
//  claudeBlastTests
//
//  Root suite that forces the whole bundle serial. Every SwiftData-touching
//  suite is declared `extension SerialTests { struct …Tests }`, making it a
//  sub-suite; `.serialized` on the parent serializes all descendants, so no two
//  tests share the single `TestStore` container at once. See TestStore.swift.
//

import Testing

@Suite(.serialized)
enum SerialTests {}

// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef OPENTITAN_SW_DEVICE_ROM_EXTS_MANIFEST_H_
#define OPENTITAN_SW_DEVICE_ROM_EXTS_MANIFEST_H_

// Header Extern Guard (so header can be used from C and C++)
#ifdef __cplusplus
extern "C" {
#endif  // __cplusplus

% for name, region in items:
/**
 * Manifest field ${name} offset from the base.
 */
#define ${region.offset_name().as_c_define()} ${region.base_addr}u

/**
 * Manifest field ${name} size in bytes and words.
 */
#define ${region.size_bytes_name().as_c_define()} ${region.size_bytes}u
#define ${region.size_words_name().as_c_define()} ${region.size_words}u

% endfor
#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  // OPENTITAN_SW_DEVICE_ROM_EXTS_MANIFEST_H_

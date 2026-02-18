# Copyright 2026 The Komandara Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

.section .text.init
.globl _start

_start:
    li   t0, 0x40001008
    li   t1, 1
    sw   t1, 0(t0)

1:  j    1b

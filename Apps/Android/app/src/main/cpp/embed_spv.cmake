# Reads a .spv file and writes a C header with a uint32_t array.
if(NOT DEFINED spv OR NOT DEFINED hdr OR NOT DEFINED sym)
  message(FATAL_ERROR "embed_spv.cmake needs -Dspv= -Dhdr= -Dsym=")
endif()
file(READ "${spv}" _bytes HEX)
string(LENGTH "${_bytes}" _hexlen)
math(EXPR _nbytes "${_hexlen} / 2")
math(EXPR _rem "${_nbytes} % 4")
if(NOT _rem EQUAL 0)
  message(FATAL_ERROR "SPIR-V ${spv} is not a multiple of 4 bytes")
endif()
set(_body "")
set(_i 0)
while(_i LESS _hexlen)
  string(SUBSTRING "${_bytes}" ${_i} 8 _word)
  string(SUBSTRING "${_word}" 6 2 b0)
  string(SUBSTRING "${_word}" 4 2 b1)
  string(SUBSTRING "${_word}" 2 2 b2)
  string(SUBSTRING "${_word}" 0 2 b3)
  string(APPEND _body "0x${b0}${b1}${b2}${b3},")
  math(EXPR _i "${_i} + 8")
endwhile()
math(EXPR _count "${_nbytes} / 4")
file(WRITE "${hdr}"
"#pragma once
#include <stdint.h>
static const uint32_t ${sym}[] = { ${_body} };
static const uint32_t ${sym}_count = ${_count}u;
")

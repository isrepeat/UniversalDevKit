#pragma once
#include <UniversalDevKit/Helpers/Std/Config.h>

#include "rangesEx/ranges_flatten_tree.h"
#include "rangesEx/ranges_drop_last.h"
#include "rangesEx/ranges_concat.h"
#include "rangesEx/ranges_to.h"

//
//  ░ Range adaptor pattern (C++23 style)
//  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
//
//  All extensions follow the same adaptor pattern:
//  • <name>_closure stores arguments and declares a hidden friend operator|.
//    The operator accesses closure state and is discovered through ADL.
// 
//  • <name>_fn implements the range operation when a separate function object
//    is useful, such as computing countToTake for drop_last.
// 
//  • The public <name>(...) factory returns a <name>_closure.
//
//  A hidden friend remains a non-member function in the enclosing namespace,
//  while retaining access to the closure's private members.
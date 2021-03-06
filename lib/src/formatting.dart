// Copyright 2013 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * Turn text into HTML elements by applying formatting rules to regular
 * expression matches.
 */
library formatting;

import 'dart:html';

/** Formatting function that turns text into HTML element based on some rules */
typedef Element Formatter(String text);

/**
 * Make a formatter for the given [map] of rules.
 *
 * Each rule is a pair of regular expression and an associated formatter that
 * will be applied to regular expression's match. Regular expression will not
 * be tried for a match in the middle of the word.
 *
 * Parts of text that do not match any rule will be wrapped into [Text].
 */
makeFormatter(Map<String, Formatter> map) {
  final actions = map.values.toList();
  final patterns = map.keys.map((re) => new RegExp("^${re}")).toList();

  return (text) {
    final result = new SpanElement();

    _apply(patterns, text, (idx, val) {
      result.nodes.add((idx != null) ?
        actions[idx](val) : new Text(val));
    });

    return result;
  };
}

/** Regular expression to skip words that do not match any rule. */
final wordRe = new RegExp(r"^[-\w]+");

/**
 * Given a list of regular expressions [patterns] invoke [callback] for every
 * match passing index of the matched expression and matched substring.
 *
 * Substrings between matches are passed to [callback] with [null] instead
 * of index.
 */
_apply(List<RegExp> patterns, String text, Function callback) {
  final unmatched = [];

  outer: while (text.length > 0) {
    for (var i = 0; i < patterns.length; i++) {
      final m = patterns[i].firstMatch(text);
      if (m != null) {
        final value = m.group(0);

        if (!unmatched.isEmpty) {  // There is a pending unmatched substring.
          callback(null, unmatched.join());
          unmatched.clear();
        }

        callback(i, value);
        text = text.substring(value.length);  // Skip matched part.
        continue outer;
      }
    }

    // No matching pattern found. If we are standing at the start of the word
    // then skip it as whole. Otherwise skip a single character.
    final wordMatch = wordRe.firstMatch(text);
    if (wordMatch != null) {
      final word = wordMatch.group(0);
      unmatched.add(word);
      text = text.substring(word.length);
    } else {
      unmatched.add(text[0]);
      text = text.substring(1);
    }
  }

  if (!unmatched.isEmpty) {  // There is a pending unmatched substring.
    callback(null, unmatched.join());
  }
}

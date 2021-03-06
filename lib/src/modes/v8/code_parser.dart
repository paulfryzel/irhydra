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

/** Parsing disassembly dumped by V8. */
library code_parser;

import 'package:irhydra/src/modes/code.dart';
import 'package:irhydra/src/modes/ir.dart' as IR;
import 'package:irhydra/src/parsing.dart' as parsing;

/** Start of the optimized code dump. */
final MARKER = "--- Optimized code ---";

canRecognize(String text) =>
  text.contains(MARKER);

/** Split [text] into separate optimized code dumps. */
List<IR.Method> preparse(String text) =>
  (new PreParser(text)..parse()).methods;

/** Parse given code dump. */
Code parse(Iterable<String> lines) => lines != null ?
  (new Parser(lines)..parse()).code : new Code.empty();

/** Class that recognizes code disassembly and deoptimization events */
class PreParser extends parsing.ParserBase {
  final methods = <IR.Method>[];

  IR.Method currentMethod;

  PreParser(text) : super(text.split('\n'));

  enterMethod(name) {
    currentMethod = new IR.Method(new IR.Name(name, null, name));
    methods.add(currentMethod);
  }

  leaveMethod() { currentMethod = null; }

  get patterns => {
    // Start of the dump.
    r"^\-\-\- Optimized code \-\-\-$": {
      r"^name = ([\w.]*)$": (name) {  // Function name.
        enterMethod(name);
      },

      r"^Instructions": {  // Disassembly of the body.
        r"^\s+;;; Safepoint table": () {
          // Code is produced during the very last compilation phase.
          if (currentMethod == null) {
            enterMethod("");
          }
          currentMethod.phases.add(new IR.Phase("Z_Code generation", code: subrange()));
          leaveMethod();
          // Leave this (instructions) and outer (code) states.
          leave(nstates: 2);
        }
      }
    },

    // Start of the deoptimization event (we drop no-name deopts)
    r"^\[deoptimizing \(DEOPT (\w+)\): begin 0x[a-f0-9]+ ([\w$.]+) @(\d+)": (type, method_name, bailout_id) {
      // TODO(vegorov): add warning about lost deopts.
      enter({
        r"^\[deoptimizing \(\w+\): end": () {
          final deopt =
              new IR.Deopt(int.parse(bailout_id), subrange(inclusive: true), isLazy: type == "lazy");

          // There is no reliable way to match deopt to the code where it
          // occured so we just attach it to the last code object with the
          // same name.
          for (var currentMethod in methods.reversed) {
            if (currentMethod.name.full == method_name) {
              currentMethod.deopts.add(deopt);
              break;
            }
          }

          leave();
        }
      });
    },
  };
}

/** Disassembly parser. */
class Parser extends parsing.ParserBase {
  final _code = [];
  final blocks = {};

  /** Base address of the code object. */
  int start;

  /** Current basic block range. */
  Range block;

  Parser(lines) : super(lines);

  get patterns => {
    // Instruction.
    r"^0x([a-f0-9]+)\s+(\d+)\s+[a-f0-9]+\s+([^;]+)(;;.*)?$": (address,
                                                              offs,
                                                              instr,
                                                              [comment]) {
      parseInstruction(int.parse(address, radix: 16), instr, comment);
    },

    // Block start.
    r"^\s+;;; <@\d+,#\d+> \-+ (B\d+)": (name) {
      if (block != null) block.end = _code.length;
      blocks[name] = block = new Range(_code.length);
    },

    // Comment.
    r"^\s+;*\s*(.*)$": (text) => parseComment(text),
  };

  /** Matches local jumps in V8 disassembly. They are formatted with offset. */
  final localJumpRe = new RegExp(r"^(j\w+) (\d+) ");

  parseInstruction(addr, instr, comment) {
    if (start == null) start = addr;

    final offset = addr - start;

    if (comment != null) {
      // Drop comment's ;;-prefix.
      comment = comment.replaceAll(new RegExp(r"^;;\s+"), "");
    }

    // Check if instruction is formatted as a local jump to an offset inside
    // this code object.
    final localJump = localJumpRe.firstMatch(instr);
    if (localJump != null) {
      final opcode = localJump.group(1);
      final target = int.parse(localJump.group(2));
      _code.add(new Jump(offset, opcode, target, comment));
      return;
    }

    // Other instructions (inluding jumps to absolute addresses).
    _code.add(new Instruction(offset, instr, comment));
  }

  parseComment(comment) {
    // If the last instruction was a "gap" or "label" comment then drop it.
    // Empty labels and gaps do not carry any interesting information.
    if (_code.last is Comment) {
      final lastComment = _code.last.comment;
      if (lastComment.contains(": gap.") ||
          lastComment.contains(": label.")) {
        _code.removeLast();
      }
    }

    // Check if we reached code epilogue containing deferred code.
    if (comment.startsWith("Deferred") && block != null) {
      block.end = _code.length;
      block = null;
    }

    _code.add(new Comment(comment));
  }

  get code {
    if (block != null) block.end = _code.length;  // Finalize last block.
    return new Code(start, _code, blocks);
  }
}

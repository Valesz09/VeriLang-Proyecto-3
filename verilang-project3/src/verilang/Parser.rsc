module verilang::Parser

import verilang::Syntax;
import verilang::AST;
import ParseTree;
import String;

// ─── Entry point ─────────────────────────────────────────────────────────────
// Parses a .vl source string and returns the Program AST node.
Program parseProgram(str src) {
    Tree cst = parse(#start[Program], src);
    return implode(#Program, cst.top);
}

// Parses from a file location.
Program parseProgramFile(loc file) {
    Tree cst = parse(#start[Program], file);
    return implode(#Program, cst.top);
}

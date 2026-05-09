module verilang::Main

// ─── Main entry point for VeriLang Project 3 ────────────────────────────────
// Usage (Rascal REPL):
//   import verilang::Main;
//   main(|project://verilang/examples/example.vl|);
// ─────────────────────────────────────────────────────────────────────────────

import verilang::CodeGen;
import IO;

void main(loc file) {
    println("Running VeriLang program: <file>");
    println("");
    runFile(file);
}

// Convenience overload accepting a string path.
void main(str path) {
    main(toLocation(path));
}

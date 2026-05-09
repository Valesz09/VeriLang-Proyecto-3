module verilang::CodeGen

// ─── Code Generation for VeriLang ────────────────────────────────────────────
// Walks the AST and produces a string representation of the program's
// evaluated result, then prints it to the console.
//
// VeriLang is a *specification* language, not a general-purpose language.
// "Running" a program means:
//   1. Printing each declared variable with its type and value (if a literal).
//   2. Printing each data structure with its fields.
//   3. Evaluating and printing each equation (LHS = RHS).
// ─────────────────────────────────────────────────────────────────────────────

import verilang::AST;
import verilang::Parser;
import verilang::Checker;

import IO;
import String;
import List;

// ─── Entry points ────────────────────────────────────────────────────────────

// Run a .vl file: parse, type-check, then print results.
void runFile(loc file) {
    str src = readFile(file);
    runSource(src, file);
}

void runSource(str src, loc origin) {
    Program prog = parseProgram(src);

    // Type-check first; report errors but continue to print partial output.
    set[Message] msgs = checkProgram(prog, origin);
    if (!isEmpty(msgs)) {
        println("=== Type errors ===");
        for (m <- msgs) println("  <m>");
        println("");
    }

    println("=== VeriLang program: <prog.name> ===");
    println("");

    for (Component comp <- prog.components) {
        printComponent(comp);
    }

    println("=== End of program ===");
}

// ─── Component printer ───────────────────────────────────────────────────────

void printComponent(spaceComp(SpaceDecl sp)) {
    switch (sp) {
        case spaceSimple(str n):     println("[Space]  <n>");
        case spaceSubspace(str n, str sup): println("[Space]  <n>  <  <sup>");
    }
}

void printComponent(operatorComp(OperatorDecl op)) {
    println("[Operator]  <op.name> : <prettyTypeExpr(op.typeExpr)>");
}

void printComponent(varComp(VarDecl vd)) {
    for (VarBinding b <- vd.bindings) {
        println("[Var]  <b.name> : <prettyBuiltin(b.tp)>");
    }
}

void printComponent(dataComp(DataDecl dd)) {
    println("[Data]  <dd.name> : <prettyBuiltin(dd.tp)>");
    for (DataField f <- dd.fields) {
        println("          field  <f.name> : <prettyBuiltin(f.tp)>");
    }
}

void printComponent(expressionComp(ExpressionDecl ed)) {
    switch (ed) {
        case expressionDeclNoAttr(Expr e):
            println("[Expression]  <prettyExpr(e)>");
        case expressionDeclAttr(Expr e, AttrList al):
            println("[Expression]  <prettyExpr(e)>  <prettyAttrs(al)>");
    }
}

void printComponent(ruleComp(RuleDecl r)) {
    println("[Rule]  <prettyApp(r.lhs)>  ->  <prettyApp(r.rhs)>");
}

void printComponent(equationComp(EquationDecl eq)) {
    println("[Equation]  <prettyExpr(eq.lhs)>  =  <prettyExpr(eq.rhs)>");
}

// ─── Pretty printers ─────────────────────────────────────────────────────────

str prettyBuiltin(typeInt())       = "Int";
str prettyBuiltin(typeBool())      = "Bool";
str prettyBuiltin(typeChar())      = "Char";
str prettyBuiltin(typeString())    = "String";
str prettyBuiltin(typeId(str n))   = n;

str prettyTypeExpr(typeBase(str n))             = n;
str prettyTypeExpr(typeArrow(str d, TypeExpr c)) = "<d> -> <prettyTypeExpr(c)>";

str prettyExpr(quantifiedExpr(Quantifier q, str v, str dom, Expr body))
    = "<prettyQ(q)> <v> in <dom> . <prettyExpr(body)>";
str prettyExpr(infixExpr(InfixExpr ie))
    = prettyInfix(ie);

str prettyQ(forall()) = "forall";
str prettyQ(exists()) = "exists";

str prettyInfix(infixSingle(SimpleExpr se)) = prettySimple(se);
str prettyInfix(infixChain(SimpleExpr l, InfixOp op, InfixExpr r))
    = "<prettySimple(l)> <prettyOp(op)> <prettyInfix(r)>";

str prettySimple(simpleApp(OperatorApp app)) = prettyApp(app);
str prettySimple(simpleParens(Expr e))       = "(<prettyExpr(e)>)";
str prettySimple(simpleId(str n))            = n;
str prettySimple(simpleInt(int v))           = "<v>:Int";
str prettySimple(simpleBool(bool v))         = "<v>:Bool";
str prettySimple(simpleChar(str v))          = "\'<v>\':Char";
str prettySimple(simpleString(str v))        = "\"<v>\":String";

str prettyApp(operatorApp(str op, list[SimpleExpr] args))
    = "(<op> <intercalate(" ", [prettySimple(a) | a <- args])>)";

str prettyOp(opAnd())   = "and";
str prettyOp(opOr())    = "or";
str prettyOp(opNeg())   = "neg";
str prettyOp(opEq())    = "=";
str prettyOp(opLt())    = "\<";
str prettyOp(opGt())    = "\>";
str prettyOp(opLte())   = "\<=";
str prettyOp(opGte())   = "\>=";
str prettyOp(opNeq())   = "\<\>";
str prettyOp(opEquiv()) = "≡";
str prettyOp(opImpl())  = "=\>";
str prettyOp(opArrow()) = "-\>";
str prettyOp(opPlus())  = "+";
str prettyOp(opMinus()) = "-";
str prettyOp(opMul())   = "*";
str prettyOp(opDiv())   = "/";
str prettyOp(opPow())   = "**";
str prettyOp(opMod())   = "%";
str prettyOp(opIn())    = "in";

str prettyAttrs(attrList(list[AttrItem] items))
    = "[<intercalate(", ", [prettyAttrItem(it) | it <- items])>]";

str prettyAttrItem(attrItemSimple(str n))          = n;
str prettyAttrItem(attrItemColon(str n, AttrValue v)) = "<n>:<prettyAttrVal(v)>";

str prettyAttrVal(attrValId(str n))  = n;
str prettyAttrVal(attrValEmpty())    = "∅";

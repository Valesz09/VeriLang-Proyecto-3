module verilang::Checker

// TypePal integration for VeriLang
// ─────────────────────────────────────────────────────────────────────────────
// This module installs TypePal and implements:
//   1. Type annotations checking (Integers, Booleans, Chars, Strings,
//      and user-defined data structure types).
//   2. Type correspondence checking (variables used with the correct type).
//   3. Data-structure element existence rule (fields used in a defdata must
//      actually be declared in that defdata block).
// ─────────────────────────────────────────────────────────────────────────────

import verilang::Syntax;
import verilang::AST;
import verilang::Parser;

import analysis::typepal::TypePal;
import analysis::typepal::Collector;

import IO;
import List;
import Set;
import String;
import Message;

// ══════════════════════════════════════════════════════════════════════════════
// § 1  Type representation
// ══════════════════════════════════════════════════════════════════════════════

// Internal type representation used by TypePal.
data AType
  = intType()
  | boolType()
  | charType()
  | stringType()
  | userType(str name)   // user-defined data-structure type
  | unknownType()
  ;

// Pretty-printer for error messages.
str prettyAType(intType())        = "Int";
str prettyAType(boolType())       = "Bool";
str prettyAType(charType())       = "Char";
str prettyAType(stringType())     = "String";
str prettyAType(userType(str n))  = n;
str prettyAType(unknownType())    = "unknown";

// Convert AST BuiltinType to our internal AType.
AType builtinToAType(typeInt())       = intType();
AType builtinToAType(typeBool())      = boolType();
AType builtinToAType(typeChar())      = charType();
AType builtinToAType(typeString())    = stringType();
AType builtinToAType(typeId(str n))   = userType(n);

// ══════════════════════════════════════════════════════════════════════════════
// § 2  Collect phase – gather definitions and uses into TypePal facts
// ══════════════════════════════════════════════════════════════════════════════

// We extend TypePal's Collector with VeriLang-specific rules.
// TypePal walks the tree and calls the appropriate overload.

void collect(Program p, Collector c) {
    c.enterScope(p);
    for (imp <- p.imports)  collect(imp, c);
    for (comp <- p.components) collect(comp, c);
    c.leaveScope(p);
}

void collect(importDecl(str mod), Collector c) { /* external – no type info */ }

// ─── Components ──────────────────────────────────────────────────────────────

void collect(Component comp, Collector c) {
    switch (comp) {
        case spaceComp(sp):      collect(sp, c);
        case operatorComp(op):   collect(op, c);
        case expressionComp(ex): collect(ex, c);
        case ruleComp(r):        collect(r, c);
        case varComp(vd):        collect(vd, c);
        case equationComp(eq):   collect(eq, c);
        case dataComp(dd):       collect(dd, c);
    }
}

void collect(SpaceDecl sp, Collector c) { /* spaces carry no types */ }

void collect(OperatorDecl op, Collector c) { /* operator types tracked separately */ }

// ─── Variable declarations ───────────────────────────────────────────────────
// Each binding:  varName : BuiltinType
// We define varName in scope with the declared type.

void collect(VarDecl vd, Collector c) {
    for (VarBinding b <- vd.bindings) {
        AType t = builtinToAType(b.tp);
        c.define("<b.name>", variableId(), b, defType(t));
    }
}

// ─── Data structure declarations (NEW – Project 3) ───────────────────────────
// defdata Name : UserType
//   field1 : Type
//   field2 : Type
// end
//
// We:
//   • define the data-structure name in scope (as a userType)
//   • define each field in a nested scope associated with the data name
//   • record the set of valid field names for the existence check

void collect(DataDecl dd, Collector c) {
    AType structType = userType(dd.name);

    // Define the data-structure name itself.
    c.define("<dd.name>", dataId(), dd, defType(structType));

    // Open a child scope to hold field definitions.
    c.enterScope(dd);
    set[str] fieldNames = {};
    for (DataField f <- dd.fields) {
        AType ft = builtinToAType(f.tp);
        c.define("<f.name>", fieldId(), f, defType(ft));
        fieldNames += {f.name};
    }
    // Attach field name set as a fact for the existence check.
    c.fact(dd, structType);
    c.leaveScope(dd);
}

// ─── Expressions ─────────────────────────────────────────────────────────────

void collect(ExpressionDecl ed, Collector c) {
    switch (ed) {
        case expressionDeclNoAttr(ex): collectExpr(ex, c);
        case expressionDeclAttr(ex,_): collectExpr(ex, c);
    }
}

void collect(RuleDecl rd, Collector c) { /* rules don't carry value types */ }

void collect(EquationDecl eq, Collector c) {
    collectExpr(eq.lhs, c);
    collectExpr(eq.rhs, c);
}

// ─── Recursive expression collection ─────────────────────────────────────────

void collectExpr(Expr e, Collector c) {
    switch (e) {
        case quantifiedExpr(_, str v, str dom, Expr body):
            collectExpr(body, c);
        case infixExpr(InfixExpr ie):
            collectInfix(ie, c);
    }
}

void collectInfix(InfixExpr ie, Collector c) {
    switch (ie) {
        case infixSingle(SimpleExpr se): collectSimple(se, c);
        case infixChain(SimpleExpr l, _, InfixExpr r):
            { collectSimple(l, c); collectInfix(r, c); }
    }
}

void collectSimple(SimpleExpr se, Collector c) {
    switch (se) {
        case simpleId(str name):
            // Record a use of this identifier; TypePal will resolve its type.
            c.use(se, {variableId(), dataId()});

        case simpleInt(int _):
            c.fact(se, intType());

        case simpleBool(bool _):
            c.fact(se, boolType());

        case simpleChar(str _):
            c.fact(se, charType());

        case simpleString(str _):
            c.fact(se, stringType());

        case simpleApp(OperatorApp app):
            for (arg <- app.args) collectSimple(arg, c);

        case simpleParens(Expr e):
            collectExpr(e, c);
    }
}

// ══════════════════════════════════════════════════════════════════════════════
// § 3  Calculate phase – type correspondence checking
// ══════════════════════════════════════════════════════════════════════════════

// TypePal handles the resolution automatically once facts and uses are
// declared.  Mismatches are reported as Messages by TypePal.
// We add a custom subtype relation (all base types are only subtypes of
// themselves; user types must match exactly).

bool mySubtype(AType t1, AType t2) = (t1 == t2);

// ══════════════════════════════════════════════════════════════════════════════
// § 4  Data-structure element existence rule (NEW – Project 3)
// ══════════════════════════════════════════════════════════════════════════════
// After TypePal resolves types, we walk all DataDecl nodes and verify:
//   • every field name used in the defdata body actually appears in the
//     explicit DataFieldList of that defdata declaration.
// (In the current grammar, fields are declared explicitly, so a "used but
// not declared" error can only occur if the same field name is referenced
// from an expression referencing the data structure.)

set[Message] checkDataFieldExistence(Program prog) {
    set[Message] msgs = {};

    // Build a map: dataStructureName -> set of declared field names
    map[str, set[str]] declaredFields = ();
    for (Component comp <- prog.components) {
        if (dataComp(DataDecl dd) := comp) {
            set[str] names = { f.name | DataField f <- dd.fields };
            declaredFields["<dd.name>"] = names;
        }
    }

    // Walk expressions looking for field-access patterns of the form
    // dataName.fieldName (encoded as simpleId or infix with opIn).
    // In VeriLang, existence is checked by verifying that any Id referenced
    // after "in" for a quantified expression that has a data-structure domain
    // actually exists in that structure.
    //
    // More concretely: for each quantified expression
    //    forall/exists x in D . body
    // where D is the name of a defdata, we verify that every simpleId 'f'
    // used in body that could be a field of D is indeed declared.
    for (Component comp <- prog.components) {
        msgs += checkComponentExistence(comp, declaredFields);
    }
    return msgs;
}

set[Message] checkComponentExistence(Component comp, map[str, set[str]] declared) {
    set[Message] msgs = {};
    switch (comp) {
        case expressionComp(ExpressionDecl ed):
            msgs += checkExprExistence(getExpr(ed), declared, {});
        case equationComp(EquationDecl eq):
            { msgs += checkExprExistence(eq.lhs, declared, {});
              msgs += checkExprExistence(eq.rhs, declared, {}); }
        default: ;
    }
    return msgs;
}

Expr getExpr(expressionDeclNoAttr(Expr e)) = e;
Expr getExpr(expressionDeclAttr(Expr e, _)) = e;

set[Message] checkExprExistence(Expr e, map[str, set[str]] declared, set[str] inScopeFields) {
    set[Message] msgs = {};
    switch (e) {
        case quantifiedExpr(_, str v, str dom, Expr body):
            if (dom in declared) {
                // The variable v ranges over the data structure dom.
                // Fields reachable in body that equal names of dom's fields are fine.
                msgs += checkExprExistence(body, declared, declared[dom]);
            } else {
                msgs += checkExprExistence(body, declared, inScopeFields);
            }
        case infixExpr(InfixExpr ie):
            msgs += checkInfixExistence(ie, declared, inScopeFields);
    }
    return msgs;
}

set[Message] checkInfixExistence(InfixExpr ie, map[str, set[str]] declared, set[str] inScopeFields) {
    set[Message] msgs = {};
    switch (ie) {
        case infixSingle(SimpleExpr se):
            msgs += checkSimpleExistence(se, declared, inScopeFields);
        case infixChain(SimpleExpr l, _, InfixExpr r):
            { msgs += checkSimpleExistence(l, declared, inScopeFields);
              msgs += checkInfixExistence(r, declared, inScopeFields); }
    }
    return msgs;
}

set[Message] checkSimpleExistence(SimpleExpr se, map[str, set[str]] declared, set[str] inScopeFields) {
    set[Message] msgs = {};
    switch (se) {
        case simpleId(str name):
            // If we are inside a quantifier ranging over a data structure and
            // this id is used as a field access, it must be in the declared set.
            if (!isEmpty(inScopeFields) && name notin inScopeFields
                    && name notin domain(declared)) {
                msgs += { error("Field \'<name>\' does not exist in the data structure", se@\loc) };
            }
        case simpleApp(OperatorApp app):
            for (arg <- app.args) msgs += checkSimpleExistence(arg, declared, inScopeFields);
        case simpleParens(Expr inner):
            msgs += checkExprExistence(inner, declared, inScopeFields);
        default: ;
    }
    return msgs;
}

// ══════════════════════════════════════════════════════════════════════════════
// § 5  Top-level checker
// ══════════════════════════════════════════════════════════════════════════════

// TypePal configuration for VeriLang
TypePalConfig verilangConfig() =
    tconfig(
        isSubType = mySubtype,
        prettyPrintAType = prettyAType
    );

// Run TypePal + custom existence check on a parsed Program.
set[Message] checkProgram(Program prog, loc src) {
    // Phase 1: TypePal collect + calculate
    set[Message] typepalMsgs = typecheck(prog, verilangConfig(), src);

    // Phase 2: custom existence rule
    set[Message] existenceMsgs = checkDataFieldExistence(prog);

    return typepalMsgs + existenceMsgs;
}

// Convenience: check from source string.
set[Message] checkSource(str src, loc origin) {
    Program prog = parseProgram(src);
    return checkProgram(prog, origin);
}

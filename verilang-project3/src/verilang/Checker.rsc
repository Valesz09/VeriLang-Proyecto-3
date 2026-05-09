module verilang::Checker

// TypePal integration for VeriLang
// ─────────────────────────────────────────────────────────────────────────────
// Este módulo instala TypePal e implementa:
// 1. Verificación de anotaciones de tipo (enteros, booleanos, caracteres, cadenas,
// y tipos de estructuras de datos definidos por el usuario).
// 2. Verificación de correspondencia de tipos (variables utilizadas con el tipo correcto).
// 3. Regla de existencia de elementos de estructuras de datos (los campos utilizados en un bloque defdata deben
// estar declarados en dicho bloque).
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


// § 1  Type representation


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


// § 2  Collect phase – gather definitions and uses into TypePal facts


// ExtendI el Collector de TypePal con reglas específicas de VeriLang.
// TypePal recorre el árbol y llama a la sobrecarga apropiada.

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
// Cada enlace: varName : BuiltinType
// Definimos varName dentro del ámbito del tipo declarado.

void collect(VarDecl vd, Collector c) {
    for (VarBinding b <- vd.bindings) {
        AType t = builtinToAType(b.tp);
        c.define("<b.name>", variableId(), b, defType(t));
    }
}

// ─── Data structure declarations (NEW - Project 3) ───────────────────────────
// defdata Name : UserType
//   field1 : Type
//   field2 : Type
// end
//
// :
// • Definir el nombre de la estructura de datos en el ámbito (como un tipo de usuario)
// • Definir cada campo en un ámbito anidado asociado al nombre de datos
// • Registrar el conjunto de nombres de campo válidos para la comprobación de existencia

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


// § 3  Calculate phase - type correspondence checking


// TypePal gestiona la resolución automáticamente una vez que se declaran los hechos y los usos.
// TypePal informa de las discrepancias como mensajes.
// Añadi una relación de subtipo personalizada (todos los tipos base son solo subtipos de sí mismos;
// los tipos de usuario deben coincidir exactamente).

bool mySubtype(AType t1, AType t2) = (t1 == t2);


// § 4  Data-structure element existence rule (NEW - Project 3)

// Después de que TypePal resuelve los tipos, recorremos todos los nodos DataDecl y verificamos:
// • que cada nombre de campo utilizado en el cuerpo de defdata aparezca realmente en la
// DataFieldList explícita de esa declaración defdata.
// (En la gramática actual, los campos se declaran explícitamente, por lo que un error de "usado pero
// no declarado" solo puede ocurrir si se hace referencia al mismo nombre de campo
// desde una expresión que hace referencia a la estructura de datos).

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

// Recorremos expresiones buscando patrones de acceso a campos de la forma
// nombreDatos.nombreCampo (codificado como simpleId o infijo con opIn).

// En VeriLang, la existencia se comprueba verificando que cualquier Id referenciado
// después de "in" para una expresión cuantificada que tiene un dominio de estructura de datos
// exista realmente en esa estructura.

//
// Más concretamente: para cada expresión cuantificada
// para todo/existe x en D . cuerpo
// donde D es el nombre de un defdata, verificamos que cada simpleId 'f'
// utilizado en el cuerpo que podría ser un campo de D esté declarado.

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
                // La variable v recorre la estructura de datos dom.
                // Los campos accesibles en el cuerpo que coincidan con los nombres de los campos del dom son válidos.
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
        // Si estamos dentro de un cuantificador que recorre una estructura de datos y
        // este ID se utiliza para acceder a un campo, debe estar en el conjunto declarado.
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


// § 5  Top-level checker


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

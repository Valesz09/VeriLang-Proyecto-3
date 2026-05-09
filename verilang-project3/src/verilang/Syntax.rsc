module verilang::Syntax

// ─── Layout ──────────────────────────────────────────────────────────────────
layout Whitespace = [\ \t\n\r]* !>> [\ \t\n\r];

// ─── Keywords ────────────────────────────────────────────────────────────────
keyword Keywords
  = "defmodule" | "using"       | "defspace"     | "defoperator"
  | "defexpression" | "defrule" | "defvar"        | "forall"
  | "exists"    | "defer"       | "end"           | "in"
  | "and"       | "or"          | "neg"
  // Type-annotation keywords (new for Project 3)
  | "Int"       | "Bool"        | "Char"          | "String"
  ;

// ─── Lexical ──────────────────────────────────────────────────────────────────
// Identifiers: start with letter, may contain letters/digits/hyphens
lexical Id = ([a-zA-Z] [a-zA-Z0-9\-]* !>> [a-zA-Z0-9\-]) \ Keywords;

// ─── Literal values (new for Project 3) ──────────────────────────────────────
// Integer literal
lexical IntLit    = [0-9]+ !>> [0-9];
// Boolean literal
lexical BoolLit   = "true" | "false";
// Character literal  e.g.  'a'
lexical CharLit   = "'" ![\'] "'";
// String literal  e.g.  "hello"
lexical StringLit = "\"" ![\"]* "\"";

// ─── Built-in types (new for Project 3) ──────────────────────────────────────
syntax BuiltinType
  = typeInt:    "Int"
  | typeBool:   "Bool"
  | typeChar:   "Char"
  | typeString: "String"
  | typeId:     Id          // user-defined data-structure type
  ;

// ─── Start symbol ────────────────────────────────────────────────────────────
start syntax Program
  = program: "defmodule" Id ImportList ComponentList "end"
  ;

// ─── Imports ─────────────────────────────────────────────────────────────────
syntax ImportList
  = importListEmpty:
  | importListCons: ImportList ImportDecl
  ;

syntax ImportDecl
  = importDecl: "using" Id
  ;

// ─── Components ──────────────────────────────────────────────────────────────
syntax ComponentList
  = componentListEmpty:
  | componentListCons: ComponentList Component
  ;

syntax Component
  = spaceComp:      SpaceDecl
  | operatorComp:   OperatorDecl
  | expressionComp: ExpressionDecl
  | ruleComp:       RuleDecl
  | varComp:        VarDecl
  | equationComp:   EquationDecl
  | dataComp:       DataDecl       // NEW for Project 3
  ;

// ─── Space Declaration ───────────────────────────────────────────────────────
syntax SpaceDecl
  = spaceDeclSimple:   "defspace" Id "end"
  | spaceDeclSubspace: "defspace" Id "\<" Id "end"
  ;

// ─── Operator Declaration ────────────────────────────────────────────────────
syntax OperatorDecl
  = operatorDecl: "defoperator" Id ":" TypeExpr "end"
  ;

// Type expressions support currying:  A -> B -> C
syntax TypeExpr
  = typeBase:  Id
  | typeArrow: Id "-\>" TypeExpr
  ;

// ─── Variable Declaration ────────────────────────────────────────────────────
// Updated for Project 3: type annotation is now a BuiltinType (or user-defined)
syntax VarDecl
  = varDecl: "defvar" {VarBinding ","}+ "end"
  ;

syntax VarBinding
  = varBinding: Id ":" BuiltinType
  ;

// ─── Data Structure Declaration (NEW – Project 3) ────────────────────────────
// defdata <Name> : <UserType>
//   field1 : Type
//   field2 : Type
// end
syntax DataDecl
  = dataDecl: "defdata" Id ":" BuiltinType DataFieldList "end"
  ;

syntax DataFieldList
  = dataFieldListEmpty:
  | dataFieldListCons: DataFieldList DataField
  ;

syntax DataField
  = dataField: Id ":" BuiltinType
  ;

// ─── Rule Declaration ────────────────────────────────────────────────────────
syntax RuleDecl
  = ruleDecl: "defrule" OperatorApp "-\>" OperatorApp "end"
  ;

syntax OperatorApp
  = operatorApp: "(" Id {SimpleExpr " "}* ")"
  ;

// ─── Equation Declaration ────────────────────────────────────────────────────
syntax EquationDecl
  = equationDecl: "defequation" Expr "=" Expr "end"
  ;

// ─── Expression Declaration ──────────────────────────────────────────────────
syntax ExpressionDecl
  = expressionDeclNoAttr: "defexpression" Expr "end"
  | expressionDeclAttr:   "defexpression" Expr AttrList "end"
  ;

// ─── Expressions ─────────────────────────────────────────────────────────────
syntax Expr
  = quantifiedExpr: Quantifier Id "in" Id "." Expr
  | infixExpr:      InfixExpr
  ;

syntax Quantifier
  = forall: "forall"
  | exists: "exists"
  ;

syntax InfixExpr
  = infixSingle: SimpleExpr
  | infixChain:  SimpleExpr InfixOp InfixExpr
  ;

// Operators (same as Project 2)
syntax InfixOp
  = opAnd:   "and"
  | opOr:    "or"
  | opNeg:   "neg"
  | opEq:    "="
  | opLt:    "\<"
  | opGt:    "\>"
  | opLte:   "\<="
  | opGte:   "\>="
  | opNeq:   "\<\>"
  | opEquiv: "≡"
  | opImpl:  "=\>"
  | opArrow: "-\>"
  | opPlus:  "+"
  | opMinus: "-"
  | opMul:   "*"
  | opDiv:   "/"
  | opPow:   "**"
  | opMod:   "%"
  | opIn:    "in"
  ;

// SimpleExpr now also includes typed literals (Project 3)
syntax SimpleExpr
  = simpleApp:    OperatorApp
  | simpleParens: "(" Expr ")"
  | simpleId:     Id
  // Typed literal values (new for Project 3)
  | simpleInt:    IntLit    ":" "Int"
  | simpleBool:   BoolLit   ":" "Bool"
  | simpleChar:   CharLit   ":" "Char"
  | simpleString: StringLit ":" "String"
  ;

// ─── Attributes ──────────────────────────────────────────────────────────────
syntax AttrList
  = attrList: "[" AttrItem+ "]"
  ;

syntax AttrItem
  = attrItemSimple: Id
  | attrItemColon:  Id ":" AttrValue
  ;

syntax AttrValue
  = attrValId:    Id
  | attrValEmpty: "∅"
  ;

// ─── Syntax Highlighting ─────────────────────────────────────────────────────
// Keywords
anno list[str] Program@\categories;
anno list[str] ImportDecl@\categories;

keyword highlight Keywords    = \category("keyword");
// Literals
keyword highlight BoolLit     = \category("constant");
lexical highlight IntLit      = \category("constant.numeric");
lexical highlight CharLit     = \category("string.quoted.single");
lexical highlight StringLit   = \category("string.quoted.double");
// Built-in types
keyword highlight BuiltinType = \category("storage.type");

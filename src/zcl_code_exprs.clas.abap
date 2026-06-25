"! ABAP expression grammars - port of @abaplint/core 2_statements/expressions/*.ts
"! One CLASS-METHOD per expression, name = EXPR_<expression_name>.
"! Each method returns a runnable tree (zcl_code_combi_node).
"! Discovered via RTTI by zcl_code_keywords.
"!
"! Initial set covers the most-referenced expressions used by the seed statements
"! in zcl_code_stmts. Extend incrementally.
CLASS zcl_code_exprs DEFINITION
  PUBLIC
  FINAL
  CREATE PRIVATE.

  PUBLIC SECTION.

    " Cond — boolean condition tree. Simplified: actual abaplint grammar is large;
    " for keyword extraction we list only its keywords.
    CLASS-METHODS expr_cond     RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.
    CLASS-METHODS expr_compare  RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.
    CLASS-METHODS expr_compare_operator RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.
    CLASS-METHODS expr_source   RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.
    CLASS-METHODS expr_target   RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.
    CLASS-METHODS expr_field    RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.
    CLASS-METHODS expr_field_chain RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.
    CLASS-METHODS expr_field_symbol RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.
    CLASS-METHODS expr_data_definition RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.
    CLASS-METHODS expr_inline_data RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.
    CLASS-METHODS expr_loop_source RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.
    CLASS-METHODS expr_loop_target RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.
    CLASS-METHODS expr_for      RETURNING VALUE(r) TYPE REF TO zcl_code_combi_node.

ENDCLASS.


CLASS zcl_code_exprs IMPLEMENTATION.

  METHOD expr_cond.
    " Cond.ts grammar boils down to comparisons joined by AND/OR/NOT/EQUIV +
    " parentheses. Keyword-relevant tokens:
    r = zcl_code_combi=>alt( VALUE #(
      ( zcl_code_combi=>str( `AND` ) )
      ( zcl_code_combi=>str( `OR` ) )
      ( zcl_code_combi=>str( `NOT` ) )
      ( zcl_code_combi=>str( `EQUIV` ) )
      ( zcl_code_combi=>expr( `COMPARE` ) ) ) ).
  ENDMETHOD.

  METHOD expr_compare.
    " Compare.ts — basic shape: Source CompareOperator Source, with IS/BETWEEN/IN/LIKE variants
    r = zcl_code_combi=>alt( VALUE #(
      ( zcl_code_combi=>str( `IS` ) )
      ( zcl_code_combi=>str( `INITIAL` ) )
      ( zcl_code_combi=>str( `BOUND` ) )
      ( zcl_code_combi=>str( `ASSIGNED` ) )
      ( zcl_code_combi=>str( `SUPPLIED` ) )
      ( zcl_code_combi=>str( `INSTANCE OF` ) )
      ( zcl_code_combi=>str( `BETWEEN` ) )
      ( zcl_code_combi=>str( `IN` ) )
      ( zcl_code_combi=>str( `LIKE` ) )
      ( zcl_code_combi=>str( `CO` ) )
      ( zcl_code_combi=>str( `CN` ) )
      ( zcl_code_combi=>str( `CA` ) )
      ( zcl_code_combi=>str( `NA` ) )
      ( zcl_code_combi=>str( `CS` ) )
      ( zcl_code_combi=>str( `NS` ) )
      ( zcl_code_combi=>str( `CP` ) )
      ( zcl_code_combi=>str( `NP` ) )
      ( zcl_code_combi=>expr( `COMPARE_OPERATOR` ) ) ) ).
  ENDMETHOD.

  METHOD expr_compare_operator.
    r = zcl_code_combi=>alt( VALUE #(
      ( zcl_code_combi=>str( `EQ` ) )
      ( zcl_code_combi=>str( `NE` ) )
      ( zcl_code_combi=>str( `LT` ) )
      ( zcl_code_combi=>str( `LE` ) )
      ( zcl_code_combi=>str( `GT` ) )
      ( zcl_code_combi=>str( `GE` ) ) ) ).
  ENDMETHOD.

  METHOD expr_source.
    " Source — value expression. For keyword purposes, the constructor expressions:
    r = zcl_code_combi=>alt( VALUE #(
      ( zcl_code_combi=>str( `VALUE` ) )
      ( zcl_code_combi=>str( `NEW` ) )
      ( zcl_code_combi=>str( `REF` ) )
      ( zcl_code_combi=>str( `CONV` ) )
      ( zcl_code_combi=>str( `CAST` ) )
      ( zcl_code_combi=>str( `EXACT` ) )
      ( zcl_code_combi=>str( `COND` ) )
      ( zcl_code_combi=>str( `SWITCH` ) )
      ( zcl_code_combi=>str( `REDUCE` ) )
      ( zcl_code_combi=>str( `FILTER` ) )
      ( zcl_code_combi=>str( `CORRESPONDING` ) )
      ( zcl_code_combi=>str( `BOOLC` ) )
      ( zcl_code_combi=>str( `XSDBOOL` ) )
      ( zcl_code_combi=>str( `LET` ) )
      ( zcl_code_combi=>str( `IN` ) )
      ( zcl_code_combi=>str( `THEN` ) )
      ( zcl_code_combi=>str( `ELSE` ) ) ) ).
  ENDMETHOD.

  METHOD expr_target.
    r = zcl_code_combi=>alt( VALUE #(
      ( zcl_code_combi=>expr( `FIELD_CHAIN` ) )
      ( zcl_code_combi=>expr( `INLINE_DATA` ) )
      ( zcl_code_combi=>expr( `FIELD_SYMBOL` ) ) ) ).
  ENDMETHOD.

  METHOD expr_field.
    r = zcl_code_combi=>tok( `Identifier` ).
  ENDMETHOD.

  METHOD expr_field_chain.
    r = zcl_code_combi=>expr( `FIELD` ).
  ENDMETHOD.

  METHOD expr_field_symbol.
    r = zcl_code_combi=>tok( `Identifier` ).
  ENDMETHOD.

  METHOD expr_data_definition.
    " DataDefinition — name + TYPE/LIKE clause + value
    r = zcl_code_combi=>seq( VALUE #(
      ( zcl_code_combi=>expr( `FIELD` ) )
      ( zcl_code_combi=>opt( zcl_code_combi=>alt( VALUE #(
          ( zcl_code_combi=>str( `TYPE` ) )
          ( zcl_code_combi=>str( `LIKE` ) ) ) ) ) )
      ( zcl_code_combi=>opt( zcl_code_combi=>str( `VALUE` ) ) )
      ( zcl_code_combi=>opt( zcl_code_combi=>str( `READ-ONLY` ) ) ) ) ).
  ENDMETHOD.

  METHOD expr_inline_data.
    r = zcl_code_combi=>tok( `Identifier` ).
  ENDMETHOD.

  METHOD expr_loop_source.
    r = zcl_code_combi=>alt( VALUE #(
      ( zcl_code_combi=>expr( `FIELD_CHAIN` ) )
      ( zcl_code_combi=>str( `SCREEN` ) ) ) ).
  ENDMETHOD.

  METHOD expr_loop_target.
    r = zcl_code_combi=>alt( VALUE #(
      ( zcl_code_combi=>seq( VALUE #(
          ( zcl_code_combi=>str( `INTO` ) )
          ( zcl_code_combi=>expr( `TARGET` ) ) ) ) )
      ( zcl_code_combi=>seq( VALUE #(
          ( zcl_code_combi=>str( `ASSIGNING` ) )
          ( zcl_code_combi=>expr( `FIELD_SYMBOL` ) ) ) ) )
      ( zcl_code_combi=>seq( VALUE #(
          ( zcl_code_combi=>str( `REFERENCE INTO` ) )
          ( zcl_code_combi=>expr( `TARGET` ) ) ) ) ) ) ).
  ENDMETHOD.

  METHOD expr_for.
    r = zcl_code_combi=>seq( VALUE #(
      ( zcl_code_combi=>str( `FOR` ) )
      ( zcl_code_combi=>opt( zcl_code_combi=>str( `EACH` ) ) )
      ( zcl_code_combi=>opt( zcl_code_combi=>str( `IN` ) ) )
      ( zcl_code_combi=>opt( zcl_code_combi=>str( `WHERE` ) ) ) ) ).
  ENDMETHOD.

ENDCLASS.

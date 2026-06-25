CLASS zcl_code_metrics_input DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.

    " Builds the minimal parse-data that ZCL_CODE_METRICS actually reads
    " (per-include CL_CI_SCAN + statement keyword list + unit boundaries),
    " natively - no full ABAP parser needed. Operand sets are not built: the
    " metrics classify tokens purely via ZCL_CODE_KEYWORDS=>is_keyword.
    "   i_type/i_name as delivered by the UI (PROG/REPS/CLAS/METH, NAME=>METHOD).
    CLASS-METHODS build
      IMPORTING
        !i_type        TYPE string
        !i_name        TYPE string
      EXPORTING
        !es_parse_data TYPE zif_code_parse_data=>ts_parse_data
        !ev_program    TYPE program.

  PRIVATE SECTION.

    CLASS-METHODS scan_include
      IMPORTING !i_include     TYPE program
      RETURNING VALUE(ro_scan) TYPE REF TO cl_ci_scan.

    " One row per statement: index = statement number, name = upper-cased first
    " token (the statement keyword). Enough to locate METHOD/ENDMETHOD/FORM/...
    CLASS-METHODS build_keywords
      IMPORTING !io_scan     TYPE REF TO cl_ci_scan
      RETURNING VALUE(rt_kw) TYPE zif_code_parse_data=>tt_kword.

    " Joins up to i_count tokens of statement i_stmt starting at offset i_off.
    CLASS-METHODS stmt_text
      IMPORTING
        !io_scan      TYPE REF TO cl_ci_scan
        !i_stmt       TYPE i
        !i_off        TYPE i DEFAULT 0
        !i_count      TYPE i DEFAULT 1
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS build_class
      IMPORTING !i_class    TYPE string
      EXPORTING
        !es_parse_data TYPE zif_code_parse_data=>ts_parse_data
        !ev_program    TYPE program.

    CLASS-METHODS build_program
      IMPORTING !i_program  TYPE program
      EXPORTING
        !es_parse_data TYPE zif_code_parse_data=>ts_parse_data
        !ev_program    TYPE program.
ENDCLASS.



CLASS zcl_code_metrics_input IMPLEMENTATION.


  METHOD build.

    DATA(lv_type) = i_type.
    DATA(lv_name) = i_name.
    TRANSLATE lv_type TO UPPER CASE.
    TRANSLATE lv_name TO UPPER CASE.
    CONDENSE lv_name.

    DATA(lv_cls) = lv_name.
    IF lv_cls CS '=>'.
      SPLIT lv_cls AT '=>' INTO lv_cls DATA(lv_ignore).
    ENDIF.

    IF lv_type CS 'CLAS' OR lv_type CS 'CLASS'
    OR lv_type CS 'METH' OR lv_name CS '=>'.
      build_class(
        EXPORTING i_class       = lv_cls
        IMPORTING es_parse_data = es_parse_data
                  ev_program    = ev_program ).
    ELSE.
      build_program(
        EXPORTING i_program     = CONV #( lv_name )
        IMPORTING es_parse_data = es_parse_data
                  ev_program    = ev_program ).
    ENDIF.

  ENDMETHOD.


  METHOD build_class.

    ev_program = cl_oo_classname_service=>get_classpool_name( clsname = CONV #( i_class ) ).
    IF ev_program IS INITIAL.
      RETURN.
    ENDIF.

    DATA ls_clskey TYPE seoclskey.
    DATA lt_meths  TYPE seop_methods_w_include.
    ls_clskey-clsname = i_class.
    CALL FUNCTION 'SEO_CLASS_GET_METHOD_INCLUDES'
      EXPORTING  clskey   = ls_clskey
      IMPORTING  includes = lt_meths
      EXCEPTIONS OTHERS   = 1.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    LOOP AT lt_meths INTO DATA(ls_mi).
      DATA(lo_scan) = scan_include( ls_mi-incname ).
      IF lo_scan IS NOT BOUND OR lo_scan->statements IS INITIAL.
        CONTINUE.
      ENDIF.

      DATA(lt_kw) = build_keywords( lo_scan ).

      APPEND VALUE zif_code_parse_data=>ts_prog(
        program    = ev_program
        include    = ls_mi-incname
        scan       = lo_scan
        t_keywords = lt_kw ) TO es_parse_data-tt_progs.

      " The method include holds exactly one METHOD ... ENDMETHOD.
      READ TABLE lt_kw INTO DATA(ls_mkw) WITH KEY name = 'METHOD'.
      CHECK sy-subrc = 0.

      APPEND VALUE zif_code_parse_data=>ts_calls_line(
        program   = ev_program
        include   = ls_mi-incname
        class     = i_class
        eventtype = 'METHOD'
        eventname = CONV #( ls_mi-cpdkey-cpdname )
        index     = ls_mkw-index
        def_ind   = 0 ) TO es_parse_data-tt_calls_line.
    ENDLOOP.

  ENDMETHOD.


  METHOD build_program.

    ev_program = i_program.

    DATA(lo_scan) = scan_include( i_program ).
    IF lo_scan IS NOT BOUND OR lo_scan->statements IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lt_kw) = build_keywords( lo_scan ).
    APPEND VALUE zif_code_parse_data=>ts_prog(
      program    = ev_program
      include    = i_program
      scan       = lo_scan
      t_keywords = lt_kw ) TO es_parse_data-tt_progs.

    " Pass 1: classify each statement keyword into a unit start.
    DATA lt_starts TYPE STANDARD TABLE OF i WITH NON-UNIQUE DEFAULT KEY.
    DATA lt_ev_idx TYPE STANDARD TABLE OF i WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_has_proc TYPE abap_bool.

    LOOP AT lt_kw INTO DATA(ls_k).
      CASE ls_k-name.
        WHEN 'FORM' OR 'MODULE' OR 'FUNCTION'.
          lv_has_proc = abap_true.
          APPEND ls_k-index TO lt_starts.
          " Procedural units: metrics finds the END keyword itself via t_keywords.
          APPEND VALUE zif_code_parse_data=>ts_calls_line(
            program   = ev_program
            include   = i_program
            eventtype = ls_k-name
            eventname = stmt_text( io_scan = lo_scan i_stmt = ls_k-index i_off = 1 i_count = 1 )
            index     = ls_k-index
            def_ind   = 0 ) TO es_parse_data-tt_calls_line.
        WHEN 'INITIALIZATION' OR 'START-OF-SELECTION' OR 'END-OF-SELECTION'
          OR 'LOAD-OF-PROGRAM' OR 'TOP-OF-PAGE' OR 'END-OF-PAGE'
          OR 'AT' OR 'GET'.
          APPEND ls_k-index TO lt_starts.
          APPEND ls_k-index TO lt_ev_idx.
      ENDCASE.
    ENDLOOP.

    SORT lt_starts.
    DATA(lv_total) = lines( lo_scan->statements ).

    " Pass 2: event blocks need an explicit end (the metrics do not search for
    " one) - it runs up to the statement before the next unit start.
    LOOP AT lt_ev_idx INTO DATA(lv_ei).
      DATA(lv_to) = lv_total.
      LOOP AT lt_starts INTO DATA(lv_s) WHERE table_line > lv_ei.
        lv_to = lv_s - 1.
        EXIT.
      ENDLOOP.
      APPEND VALUE zif_code_parse_data=>ts_event(
        program    = ev_program
        include    = i_program
        name       = stmt_text( io_scan = lo_scan i_stmt = lv_ei i_off = 0 i_count = 3 )
        stmnt_from = lv_ei
        stmnt_to   = lv_to ) TO es_parse_data-t_events.
    ENDLOOP.

    " A report with neither events nor procedures (code straight under an
    " implicit START-OF-SELECTION): treat the whole source as one unit so it
    " still gets metrics.
    IF lt_ev_idx IS INITIAL AND lv_has_proc = abap_false AND lv_total > 0.
      APPEND VALUE zif_code_parse_data=>ts_event(
        program    = ev_program
        include    = i_program
        name       = CONV #( i_program )
        stmnt_from = 1
        stmnt_to   = lv_total ) TO es_parse_data-t_events.
    ENDIF.

  ENDMETHOD.


  METHOD scan_include.

    TRY.
        DATA(lo_src) = cl_ci_source_include=>create( p_name = i_include ).
        ro_scan = NEW cl_ci_scan( p_include = lo_src ).
      CATCH cx_root.
        CLEAR ro_scan.
    ENDTRY.

  ENDMETHOD.


  METHOD build_keywords.

    LOOP AT io_scan->statements INTO DATA(ls_stmt).
      DATA(lv_idx) = sy-tabix.
      DATA lv_name TYPE string.
      CLEAR lv_name.
      READ TABLE io_scan->tokens INDEX ls_stmt-from INTO DATA(ls_tok).
      IF sy-subrc = 0.
        lv_name = to_upper( ls_tok-str ).
      ENDIF.
      APPEND VALUE zif_code_parse_data=>ts_kword(
        include = ''
        index   = lv_idx
        name    = lv_name ) TO rt_kw.
    ENDLOOP.

  ENDMETHOD.


  METHOD stmt_text.

    READ TABLE io_scan->statements INDEX i_stmt INTO DATA(ls_stmt).
    CHECK sy-subrc = 0.

    DATA(lv_first) = ls_stmt-from + i_off.
    DATA(lv_last)  = lv_first + i_count - 1.
    IF lv_last > ls_stmt-to.
      lv_last = ls_stmt-to.
    ENDIF.

    DATA lv_i TYPE i.
    lv_i = lv_first.
    WHILE lv_i <= lv_last.
      READ TABLE io_scan->tokens INDEX lv_i INTO DATA(ls_tok).
      IF sy-subrc = 0 AND ls_tok-str IS NOT INITIAL.
        IF rv_text IS NOT INITIAL.
          rv_text = rv_text && ` `.
        ENDIF.
        rv_text = rv_text && ls_tok-str.
      ENDIF.
      lv_i = lv_i + 1.
    ENDWHILE.

  ENDMETHOD.

ENDCLASS.

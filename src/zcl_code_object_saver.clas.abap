CLASS zcl_code_object_saver DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS save
      IMPORTING
        i_object_type TYPE string
        i_object_name TYPE string
        i_source      TYPE string
        i_package     TYPE string OPTIONAL
      RETURNING
        VALUE(rv_message) TYPE string.
    CLASS-METHODS get_last_log
      RETURNING
        VALUE(rv_log) TYPE string.

  PRIVATE SECTION.
    TYPES ty_source_line TYPE c LENGTH 255.
    TYPES tt_source      TYPE STANDARD TABLE OF ty_source_line WITH NON-UNIQUE DEFAULT KEY.
    CLASS-DATA mv_last_log TYPE string.

    CLASS-METHODS save_program
      IMPORTING
        i_program TYPE string
        i_source  TYPE string
        i_package TYPE string OPTIONAL
      RETURNING
        VALUE(rv_message) TYPE string.

    CLASS-METHODS source_to_table
      IMPORTING
        i_source TYPE string
      RETURNING
        VALUE(rt_source) TYPE tt_source.

    CLASS-METHODS syntax_check
      IMPORTING
        it_source TYPE tt_source
      RETURNING
        VALUE(rv_message) TYPE string.

    CLASS-METHODS program_exists
      IMPORTING
        i_program TYPE progname
      RETURNING
        VALUE(rv_exists) TYPE abap_bool.

    CLASS-METHODS verify_inactive_source
      IMPORTING
        i_program TYPE progname
        it_source TYPE tt_source
        i_existed TYPE abap_bool
      RETURNING
        VALUE(rv_message) TYPE string.

    CLASS-METHODS get_program_dir
      IMPORTING
        i_program TYPE progname
        i_source  TYPE string
      RETURNING
        VALUE(rs_progdir) TYPE zif_abapgit_sap_report=>ty_progdir.
ENDCLASS.



CLASS zcl_code_object_saver IMPLEMENTATION.


  METHOD get_program_dir.

    TRY.
        rs_progdir = zcl_abapgit_factory=>get_sap_report( )->read_progdir( i_program ).
      CATCH cx_root.
        CLEAR rs_progdir.
    ENDTRY.

    IF rs_progdir-name IS NOT INITIAL.
      RETURN.
    ENDIF.

    rs_progdir-name = i_program.
    rs_progdir-state = 'I'.
    rs_progdir-fixpt = abap_true.
    rs_progdir-uccheck = abap_true.

    DATA(lv_source_upper) = i_source.
    TRANSLATE lv_source_upper TO UPPER CASE.
    IF lv_source_upper CS 'REPORT ' OR lv_source_upper CS 'PROGRAM '.
      rs_progdir-subc = '1'.
    ELSE.
      rs_progdir-subc = 'I'.
    ENDIF.

  ENDMETHOD.


  METHOD get_last_log.

    rv_log = mv_last_log.

  ENDMETHOD.


  METHOD program_exists.

    DATA lv_progname TYPE reposrc-progname.

    SELECT SINGLE progname
      FROM reposrc
      INTO lv_progname
      WHERE progname = i_program.

    rv_exists = xsdbool( sy-subrc = 0 ).

  ENDMETHOD.


  METHOD save.

    CLEAR mv_last_log.

    DATA(lv_object_type) = i_object_type.
    TRANSLATE lv_object_type TO UPPER CASE.

    CASE lv_object_type.
      WHEN 'REPS' OR 'PROG' OR 'PROGRAM' OR 'REPORT'.
        rv_message = save_program(
          i_program = i_object_name
          i_source  = i_source
          i_package = i_package ).
      WHEN OTHERS.
        rv_message = |Saving { i_object_type } { i_object_name } is not implemented yet.|.
        mv_last_log = rv_message.
    ENDCASE.

  ENDMETHOD.


  METHOD save_program.

    DATA lv_program TYPE progname.
    DATA lv_package TYPE devclass.
    DATA lv_title TYPE rglif-title.
    DATA lt_source TYPE tt_source.
    DATA ls_progdir TYPE zif_abapgit_sap_report=>ty_progdir.

    lv_program = i_program.
    TRANSLATE lv_program TO UPPER CASE.
    CONDENSE lv_program.

    IF lv_program IS INITIAL.
      rv_message = 'Program name is empty.'.
      mv_last_log = rv_message.
      RETURN.
    ENDIF.

    lt_source = source_to_table( i_source ).
    IF lt_source IS INITIAL.
      rv_message = |No source code to save for program { lv_program }.|.
      mv_last_log = rv_message.
      RETURN.
    ENDIF.

    DATA(lv_syntax_error) = syntax_check( lt_source ).
    IF lv_syntax_error IS NOT INITIAL.
      rv_message = lv_syntax_error.
      mv_last_log = rv_message.
      RETURN.
    ENDIF.

    DATA(lv_exists) = program_exists( lv_program ).
    lv_package = i_package.
    TRANSLATE lv_package TO UPPER CASE.
    CONDENSE lv_package.
    IF lv_package IS INITIAL.
      lv_package = '$TMP'.
    ENDIF.

    ls_progdir = get_program_dir(
      i_program = lv_program
      i_source  = i_source ).
    lv_title = lv_program.

    mv_last_log = |SAVE_OBJECT diagnostics|
               && cl_abap_char_utilities=>newline
               && |Object: PROG { lv_program }|
               && cl_abap_char_utilities=>newline
               && |Package: { lv_package }|
               && cl_abap_char_utilities=>newline
               && |Object existed before save: { lv_exists }|
               && cl_abap_char_utilities=>newline
               && |Proposed source lines: { lines( lt_source ) }|
               && cl_abap_char_utilities=>newline
               && |PROPOSED SOURCE:|
               && cl_abap_char_utilities=>newline
               && i_source.

    TRY.
        IF lv_exists = abap_false.
          zcl_abapgit_factory=>get_cts_api( )->insert_transport_object(
            iv_object   = 'ABAP'
            iv_obj_name = lv_program
            iv_package  = lv_package
            iv_language = sy-langu ).

          TRY.
              CALL FUNCTION 'RPY_PROGRAM_INSERT'
                EXPORTING
                  development_class = lv_package
                  program_name      = lv_program
                  program_type      = ls_progdir-subc
                  title_string      = lv_title
                  save_inactive     = 'I'
                  suppress_dialog   = abap_true
                  uccheck           = ls_progdir-uccheck
                TABLES
                  source_extended   = lt_source
                EXCEPTIONS
                  already_exists    = 1
                  cancelled         = 2
                  name_not_allowed  = 3
                  permission_error  = 4
                  OTHERS            = 5.
            CATCH cx_sy_dyn_call_param_not_found.
              CALL FUNCTION 'RPY_PROGRAM_INSERT'
                EXPORTING
                  development_class = lv_package
                  program_name      = lv_program
                  program_type      = ls_progdir-subc
                  title_string      = lv_title
                  save_inactive     = 'I'
                  suppress_dialog   = abap_true
                TABLES
                  source_extended   = lt_source
                EXCEPTIONS
                  already_exists    = 1
                  cancelled         = 2
                  name_not_allowed  = 3
                  permission_error  = 4
                  OTHERS            = 5.
          ENDTRY.
          IF sy-subrc <> 0.
            rv_message = |Error creating program { lv_program }: { sy-msgid } { sy-msgno } { sy-msgv1 } { sy-msgv2 }|.
            mv_last_log = mv_last_log
                       && cl_abap_char_utilities=>newline
                       && rv_message.
            RETURN.
          ENDIF.
        ELSE.
          CALL FUNCTION 'RPY_INCLUDE_UPDATE'
            EXPORTING
              include_name     = lv_program
              title_string     = lv_title
              save_inactive    = 'I'
            TABLES
              source_extended  = lt_source
            EXCEPTIONS
              not_found        = 1
              cancelled        = 2
              permission_error = 3
              OTHERS           = 4.
          IF sy-subrc <> 0.
            rv_message = |Error updating program { lv_program }: { sy-msgid } { sy-msgno } { sy-msgv1 } { sy-msgv2 }|.
            mv_last_log = mv_last_log
                       && cl_abap_char_utilities=>newline
                       && rv_message.
            RETURN.
          ENDIF.
        ENDIF.

        zcl_abapgit_factory=>get_sap_report( )->update_progdir(
          is_progdir = ls_progdir
          iv_package = lv_package
          iv_state   = 'I' ).

        zcl_abapgit_objects_activation=>add(
          iv_type = 'REPS'
          iv_name = lv_program ).
      CATCH cx_root INTO DATA(lx_error).
        rv_message = |Error saving program { lv_program }: { lx_error->get_text( ) }|.
        mv_last_log = mv_last_log
                   && cl_abap_char_utilities=>newline
                   && rv_message.
        RETURN.
    ENDTRY.

    COMMIT WORK AND WAIT.
    mv_last_log = mv_last_log
               && cl_abap_char_utilities=>newline
               && |COMMIT WORK AND WAIT executed.|.

    DATA(lv_verify_message) = verify_inactive_source(
      i_program = lv_program
      it_source = lt_source
      i_existed = lv_exists ).
    IF lv_verify_message IS NOT INITIAL.
      rv_message = lv_verify_message.
      mv_last_log = mv_last_log
                 && cl_abap_char_utilities=>newline
                 && rv_message.
      RETURN.
    ENDIF.

    rv_message = COND string(
      WHEN lv_exists = abap_true
      THEN |Program { lv_program } was saved as inactive version.|
      ELSE |Program { lv_program } was created in package { lv_package } as inactive version.| ).
    mv_last_log = mv_last_log
               && cl_abap_char_utilities=>newline
               && rv_message.

  ENDMETHOD.


  METHOD source_to_table.

    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_line TYPE string.
    DATA ls_source TYPE ty_source_line.

    SPLIT i_source AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    LOOP AT lt_lines INTO lv_line.
      CLEAR ls_source.
      ls_source = lv_line.
      APPEND ls_source TO rt_source.
    ENDLOOP.

  ENDMETHOD.


  METHOD syntax_check.

    DATA lv_message TYPE string.
    DATA lv_line TYPE i.
    DATA lv_word TYPE string.

    SYNTAX-CHECK FOR it_source
      MESSAGE lv_message
      LINE lv_line
      WORD lv_word.

    IF sy-subrc <> 0.
      rv_message = |Syntax error before save: line { lv_line }, word { lv_word }: { lv_message }|.
    ENDIF.

  ENDMETHOD.


  METHOD verify_inactive_source.

    DATA lt_saved TYPE tt_source.
    DATA lt_active TYPE tt_source.
    DATA lv_active_subrc TYPE sy-subrc.

    READ REPORT i_program INTO lt_saved STATE 'I'.
    mv_last_log = mv_last_log
               && cl_abap_char_utilities=>newline
               && |READ REPORT STATE I subrc: { sy-subrc }, lines: { lines( lt_saved ) }|.
    IF sy-subrc <> 0.
      rv_message = |Program { i_program } was written, but inactive source cannot be read back.|.
      RETURN.
    ENDIF.

    mv_last_log = mv_last_log
               && cl_abap_char_utilities=>newline
               && |Inactive source equals proposed source: { xsdbool( lt_saved = it_source ) }|.
    IF lt_saved <> it_source.
      rv_message = |Program { i_program } was written, but inactive source differs from proposed source.|.
      RETURN.
    ENDIF.

    READ REPORT i_program INTO lt_active STATE 'A'.
    lv_active_subrc = sy-subrc.
    mv_last_log = mv_last_log
               && cl_abap_char_utilities=>newline
               && |READ REPORT STATE A subrc: { lv_active_subrc }, lines: { lines( lt_active ) }|
               && cl_abap_char_utilities=>newline
               && |Active source equals proposed source: { xsdbool( lt_active = it_source ) }|
               && cl_abap_char_utilities=>newline
               && |Active source equals inactive source: { xsdbool( lt_active = lt_saved ) }|.

    IF i_existed = abap_true
    AND lv_active_subrc = 0
    AND lt_active = it_source.
      rv_message = |No SE38 delta for { i_program }: proposed source is identical to active source.|.
      RETURN.
    ENDIF.

    IF i_existed = abap_true
    AND lv_active_subrc = 0
    AND lt_active = lt_saved.
      rv_message = |No SE38 delta for { i_program}: inactive source is still identical to active source.|.
    ENDIF.

  ENDMETHOD.
ENDCLASS.

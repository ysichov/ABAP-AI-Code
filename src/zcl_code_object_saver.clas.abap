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

  PRIVATE SECTION.
    TYPES ty_source_line TYPE c LENGTH 255.
    TYPES tt_source      TYPE STANDARD TABLE OF ty_source_line WITH NON-UNIQUE DEFAULT KEY.

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


  METHOD program_exists.

    DATA lv_progname TYPE reposrc-progname.

    SELECT SINGLE progname
      FROM reposrc
      INTO lv_progname
      WHERE progname = i_program.

    rv_exists = xsdbool( sy-subrc = 0 ).

  ENDMETHOD.


  METHOD save.

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
    ENDCASE.

  ENDMETHOD.


  METHOD save_program.

    DATA lv_program TYPE progname.
    DATA lv_package TYPE devclass.
    DATA lt_source TYPE tt_source.
    DATA ls_progdir TYPE zif_abapgit_sap_report=>ty_progdir.

    lv_program = i_program.
    TRANSLATE lv_program TO UPPER CASE.
    CONDENSE lv_program.

    IF lv_program IS INITIAL.
      rv_message = 'Program name is empty.'.
      RETURN.
    ENDIF.

    lt_source = source_to_table( i_source ).
    IF lt_source IS INITIAL.
      rv_message = |No source code to save for program { lv_program }.|.
      RETURN.
    ENDIF.

    DATA(lv_syntax_error) = syntax_check( lt_source ).
    IF lv_syntax_error IS NOT INITIAL.
      rv_message = lv_syntax_error.
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

    TRY.
        IF lv_exists = abap_false.
          zcl_abapgit_factory=>get_cts_api( )->insert_transport_object(
            iv_object   = 'ABAP'
            iv_obj_name = lv_program
            iv_package  = lv_package
            iv_language = sy-langu ).

          zcl_abapgit_factory=>get_sap_report( )->insert_report(
            iv_name         = lv_program
            iv_package      = lv_package
            it_source       = lt_source
            iv_state        = 'I'
            iv_version      = ls_progdir-uccheck
            iv_program_type = ls_progdir-subc ).
        ELSE.
          zcl_abapgit_factory=>get_sap_report( )->update_report(
            iv_name         = lv_program
            iv_package      = lv_package
            it_source       = lt_source
            iv_state        = 'I'
            iv_version      = ls_progdir-uccheck
            iv_program_type = ls_progdir-subc ).
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
        RETURN.
    ENDTRY.

    COMMIT WORK AND WAIT.

    DATA(lv_verify_message) = verify_inactive_source(
      i_program = lv_program
      it_source = lt_source ).
    IF lv_verify_message IS NOT INITIAL.
      rv_message = lv_verify_message.
      RETURN.
    ENDIF.

    rv_message = COND string(
      WHEN lv_exists = abap_true
      THEN |Program { lv_program } was saved as inactive version.|
      ELSE |Program { lv_program } was created in package { lv_package } as inactive version.| ).

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

    READ REPORT i_program INTO lt_saved STATE 'I'.
    IF sy-subrc <> 0.
      rv_message = |Program { i_program } was written, but inactive source cannot be read back.|.
      RETURN.
    ENDIF.

    IF lt_saved <> it_source.
      rv_message = |Program { i_program } was written, but inactive source differs from proposed source.|.
    ENDIF.

  ENDMETHOD.
ENDCLASS.

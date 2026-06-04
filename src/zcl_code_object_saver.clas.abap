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

    CLASS-METHODS check_program_syntax
      IMPORTING
        i_source TYPE string
      RETURNING
        VALUE(rv_message) TYPE string.
  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_progdir,
        name    TYPE progdir-name,
        state   TYPE progdir-state,
        subc    TYPE progdir-subc,
        fixpt   TYPE progdir-fixpt,
        uccheck TYPE progdir-uccheck,
      END OF ty_progdir.
    TYPES tt_source TYPE abaptxt255_tab.
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

    CLASS-METHODS get_existing_package
      IMPORTING
        i_program TYPE progname
      RETURNING
        VALUE(rv_package) TYPE devclass.

    CLASS-METHODS request_package_for_new_object
      IMPORTING
        i_program TYPE progname
      RETURNING
        VALUE(rv_package) TYPE devclass.

    CLASS-METHODS register_program
      IMPORTING
        i_program TYPE progname
        i_package TYPE devclass
      RETURNING
        VALUE(rv_message) TYPE string.

    CLASS-METHODS set_default_package
      IMPORTING
        i_package TYPE devclass.

    CLASS-METHODS update_program_dir
      IMPORTING
        i_program    TYPE progname
        is_progdir   TYPE ty_progdir
      RETURNING
        VALUE(rv_message) TYPE string.

    CLASS-METHODS verify_inactive_source
      IMPORTING
        i_program TYPE progname
        it_source TYPE tt_source
        i_existed TYPE abap_bool
      RETURNING
        VALUE(rv_message) TYPE string.

    CLASS-METHODS activate_program
      IMPORTING
        i_program TYPE progname
      RETURNING
        VALUE(rv_message) TYPE string.

    CLASS-METHODS get_program_dir
      IMPORTING
        i_program TYPE progname
        i_source  TYPE string
      RETURNING
        VALUE(rs_progdir) TYPE ty_progdir.

    CLASS-METHODS save_method
      IMPORTING
        i_class   TYPE string
        i_method  TYPE string
        i_source  TYPE string
      RETURNING
        VALUE(rv_message) TYPE string.
ENDCLASS.



CLASS zcl_code_object_saver IMPLEMENTATION.


  METHOD get_program_dir.

    DATA ls_sapdir TYPE progdir.

    CALL FUNCTION 'READ_PROGDIR'
      EXPORTING
        i_progname = i_program
        i_state    = 'A'
      IMPORTING
        e_progdir  = ls_sapdir
      EXCEPTIONS
        not_exists = 1
        OTHERS     = 2.
    IF sy-subrc = 0.
      MOVE-CORRESPONDING ls_sapdir TO rs_progdir.
    ENDIF.

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


  METHOD get_existing_package.

    SELECT SINGLE devclass
      FROM tadir
      INTO rv_package
      WHERE pgmid = 'R3TR'
        AND object = 'PROG'
        AND obj_name = i_program.
    IF sy-subrc = 0.
      RETURN.
    ENDIF.

    SELECT SINGLE devclass
      FROM tadir
      INTO rv_package
      WHERE pgmid = 'R3TR'
        AND object = 'REPS'
        AND obj_name = i_program.

  ENDMETHOD.


  METHOD request_package_for_new_object.

    DATA lt_fields TYPE STANDARD TABLE OF sval WITH NON-UNIQUE DEFAULT KEY.
    DATA ls_field TYPE sval.
    DATA lv_returncode TYPE c LENGTH 1.

    ls_field-tabname = 'TADIR'.
    ls_field-fieldname = 'DEVCLASS'.
    ls_field-value = '$TMP'.
    APPEND ls_field TO lt_fields.

    CALL FUNCTION 'POPUP_GET_VALUES'
      EXPORTING
        popup_title     = |Package for new program { i_program }|
      IMPORTING
        returncode      = lv_returncode
      TABLES
        fields          = lt_fields
      EXCEPTIONS
        error_in_fields = 1
        OTHERS          = 2.
    IF sy-subrc <> 0
    OR lv_returncode = 'A'.
      RETURN.
    ENDIF.

    READ TABLE lt_fields INTO ls_field INDEX 1.
    IF sy-subrc = 0.
      rv_package = ls_field-value.
      TRANSLATE rv_package TO UPPER CASE.
      CONDENSE rv_package.
      IF rv_package CS '<'
      OR rv_package CS '>'.
        CLEAR rv_package.
      ENDIF.
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

    CLEAR mv_last_log.

    DATA(lv_object_type) = i_object_type.
    TRANSLATE lv_object_type TO UPPER CASE.

    CASE lv_object_type.
      WHEN 'REPS' OR 'PROG' OR 'PROGRAM' OR 'REPORT'
        OR 'CLASS' OR 'CLAS'.
        rv_message = save_program(
          i_program = i_object_name
          i_source  = i_source
          i_package = i_package ).
      WHEN 'METH' OR 'METHOD'.
        DATA(lv_meth_cls) = i_object_name.
        DATA(lv_meth_mth) = VALUE string( ).
        IF i_object_name CS '=>'.
          SPLIT i_object_name AT '=>' INTO lv_meth_cls lv_meth_mth.
        ENDIF.
        TRANSLATE lv_meth_cls TO UPPER CASE.
        TRANSLATE lv_meth_mth TO UPPER CASE.
        CONDENSE lv_meth_cls. CONDENSE lv_meth_mth.
        rv_message = save_method(
          i_class  = lv_meth_cls
          i_method = lv_meth_mth
          i_source = i_source ).
      WHEN OTHERS.
        rv_message = |Saving { i_object_type } { i_object_name } is not implemented yet.|.
        mv_last_log = rv_message.
    ENDCASE.

    IF mv_last_log IS NOT INITIAL.
      rv_message = mv_last_log.
    ENDIF.

  ENDMETHOD.


  METHOD check_program_syntax.

    rv_message = syntax_check( source_to_table( i_source ) ).

  ENDMETHOD.


  METHOD save_program.

    DATA lv_program TYPE progname.
    DATA lv_package TYPE devclass.
    DATA lv_title TYPE rglif-title.
    DATA lv_t100_message TYPE string.
    DATA lv_error_text TYPE string.
    DATA lt_source TYPE tt_source.
    DATA ls_progdir TYPE ty_progdir.

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

    DATA(lv_exists) = program_exists( lv_program ).
    lv_package = i_package.
    TRANSLATE lv_package TO UPPER CASE.
    CONDENSE lv_package.
    IF lv_package CS '<'
    OR lv_package CS '>'.
      CLEAR lv_package.
    ENDIF.

    IF lv_exists = abap_true.
      DATA(lv_existing_package) = get_existing_package( lv_program ).
      IF lv_existing_package IS NOT INITIAL.
        lv_package = lv_existing_package.
      ENDIF.
    ELSEIF lv_package IS INITIAL.
      lv_package = request_package_for_new_object( lv_program ).
    ENDIF.

    IF lv_package IS INITIAL.
      IF lv_exists = abap_true.
        lv_package = '$TMP'.
      ELSE.
        rv_message = |Package is required for new program { lv_program }.|.
        mv_last_log = rv_message.
        RETURN.
      ENDIF.
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
        set_default_package( lv_package ).
        mv_last_log = mv_last_log
                   && cl_abap_char_utilities=>newline
                   && |Default package exported to memory ID EUK: { lv_package }|.

        DATA(lv_register_error) = register_program(
          i_program = lv_program
          i_package = lv_package ).
        IF lv_register_error IS NOT INITIAL.
          rv_message = lv_register_error.
          mv_last_log = mv_last_log
                     && cl_abap_char_utilities=>newline
                     && rv_message.
          RETURN.
        ENDIF.
        mv_last_log = mv_last_log
                   && cl_abap_char_utilities=>newline
                   && |RS_CORR_INSERT executed for ABAP { lv_program }.|.

        IF lv_exists = abap_false.
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
            MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4
              INTO lv_t100_message.
            CONCATENATE 'Error creating program' lv_program ':'
                        lv_t100_message
                   INTO rv_message SEPARATED BY space.
            mv_last_log = mv_last_log
                       && cl_abap_char_utilities=>newline
                       && rv_message.
            RETURN.
          ENDIF.
        ELSE.
          set_default_package( lv_package ).
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
            MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4
              INTO lv_t100_message.
            CONCATENATE 'Error updating program' lv_program ':'
                        lv_t100_message
                   INTO rv_message SEPARATED BY space.
            mv_last_log = mv_last_log
                       && cl_abap_char_utilities=>newline
                       && rv_message.
            RETURN.
          ENDIF.
        ENDIF.

        DATA(lv_progdir_error) = update_program_dir(
          i_program  = lv_program
          is_progdir = ls_progdir ).
        IF lv_progdir_error IS NOT INITIAL.
          rv_message = lv_progdir_error.
          mv_last_log = mv_last_log
                     && cl_abap_char_utilities=>newline
                     && rv_message.
          RETURN.
        ENDIF.
        mv_last_log = mv_last_log
                   && cl_abap_char_utilities=>newline
                   && |UPDATE_PROGDIR executed for inactive version of { lv_program }.|.

      CATCH cx_root INTO DATA(lx_error).
        lv_error_text = lx_error->get_text( ).
        CONCATENATE 'Error saving program' lv_program ':'
                    lv_error_text
               INTO rv_message SEPARATED BY space.
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

    DATA(lv_syntax_error) = syntax_check( lt_source ).
    IF lv_syntax_error IS NOT INITIAL.
      REPLACE FIRST OCCURRENCE OF 'Syntax error before save:'
        IN lv_syntax_error WITH 'Syntax error after save:'.
      rv_message = lv_syntax_error.
      mv_last_log = mv_last_log
                 && cl_abap_char_utilities=>newline
                 && rv_message.
      RETURN.
    ENDIF.
    mv_last_log = mv_last_log
               && cl_abap_char_utilities=>newline
               && |Syntax check after save passed for { lv_program }.|.

    DATA(lv_activation_message) = activate_program( lv_program ).
    IF lv_activation_message IS NOT INITIAL.
      rv_message = lv_activation_message.
      mv_last_log = mv_last_log
                 && cl_abap_char_utilities=>newline
                 && rv_message.
      RETURN.
    ENDIF.
    mv_last_log = mv_last_log
               && cl_abap_char_utilities=>newline
               && |RS_WORKING_OBJECTS_ACTIVATE executed for { lv_program }.|.

    IF lv_exists = abap_true.
      CONCATENATE 'Program' lv_program 'was saved and activated.'
             INTO rv_message SEPARATED BY space.
    ELSE.
      CONCATENATE 'Program' lv_program 'was created in package' lv_package
                  'and activated.'
             INTO rv_message SEPARATED BY space.
    ENDIF.
    mv_last_log = mv_last_log
               && cl_abap_char_utilities=>newline
               && rv_message.

  ENDMETHOD.


  METHOD activate_program.

    DATA lt_objects TYPE STANDARD TABLE OF dwinactiv WITH NON-UNIQUE DEFAULT KEY.
    DATA ls_object TYPE dwinactiv.
    DATA lv_t100_message TYPE string.
    DATA lv_subrc_text TYPE string.

    ls_object-object = 'REPS'.
    ls_object-obj_name = i_program.
    APPEND ls_object TO lt_objects.

    TRY.
        CALL FUNCTION 'RS_WORKING_OBJECTS_ACTIVATE'
          EXPORTING
            activate_ddic_objects  = abap_false
            with_popup             = abap_false
            ui_decoupled           = abap_true
          TABLES
            objects                = lt_objects
          EXCEPTIONS
            excecution_error       = 1
            cancelled              = 2
            insert_into_corr_error = 3
            OTHERS                 = 4.
      CATCH cx_sy_dyn_call_param_not_found.
        CALL FUNCTION 'RS_WORKING_OBJECTS_ACTIVATE'
          EXPORTING
            activate_ddic_objects  = abap_false
            with_popup             = abap_false
          TABLES
            objects                = lt_objects
          EXCEPTIONS
            excecution_error       = 1
            cancelled              = 2
            insert_into_corr_error = 3
            OTHERS                 = 4.
    ENDTRY.

    IF sy-subrc <> 0.
      IF sy-msgid IS NOT INITIAL.
        MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
          WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4
          INTO lv_t100_message.
      ELSE.
        lv_subrc_text = sy-subrc.
        CONCATENATE 'subrc' lv_subrc_text
               INTO lv_t100_message SEPARATED BY space.
      ENDIF.
      CONCATENATE 'Error activating program' i_program ':'
                  lv_t100_message
             INTO rv_message SEPARATED BY space.
    ENDIF.

  ENDMETHOD.


  METHOD source_to_table.

    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    DATA lv_line TYPE string.
    DATA ls_source LIKE LINE OF rt_source.

    SPLIT i_source AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.
    LOOP AT lt_lines INTO lv_line.
      CLEAR ls_source.
      ls_source = lv_line.
      APPEND ls_source TO rt_source.
    ENDLOOP.

  ENDMETHOD.


  METHOD register_program.

    DATA lv_t100_message TYPE string.

    CALL FUNCTION 'RS_CORR_INSERT'
      EXPORTING
        object              = i_program
        object_class        = 'ABAP'
        devclass            = i_package
        master_language     = sy-langu
        mode                = 'I'
        global_lock         = abap_true
        suppress_dialog     = abap_true
      EXCEPTIONS
        cancelled           = 1
        permission_failure  = 2
        unknown_objectclass = 3
        OTHERS              = 4.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
        WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4
        INTO lv_t100_message.
      CONCATENATE 'Error registering program' i_program
                  'in package' i_package ':'
                  lv_t100_message
             INTO rv_message SEPARATED BY space.
    ENDIF.

  ENDMETHOD.


  METHOD set_default_package.

    EXPORT current_devclass FROM i_package TO MEMORY ID 'EUK'.

  ENDMETHOD.


  METHOD update_program_dir.

    DATA ls_progdir TYPE progdir.
    DATA lv_t100_message TYPE string.

    CALL FUNCTION 'READ_PROGDIR'
      EXPORTING
        i_progname = i_program
        i_state    = 'I'
      IMPORTING
        e_progdir  = ls_progdir
      EXCEPTIONS
        not_exists = 1
        OTHERS     = 2.
    IF sy-subrc <> 0.
      CONCATENATE 'Error reading inactive program directory for' i_program
             INTO rv_message SEPARATED BY space.
      RETURN.
    ENDIF.

    ls_progdir-subc = is_progdir-subc.
    ls_progdir-fixpt = is_progdir-fixpt.
    ls_progdir-uccheck = is_progdir-uccheck.

    CALL FUNCTION 'UPDATE_PROGDIR'
      EXPORTING
        i_progdir    = ls_progdir
        i_progname   = ls_progdir-name
        i_state      = ls_progdir-state
      EXCEPTIONS
        not_executed = 1
        OTHERS       = 2.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
        WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4
        INTO lv_t100_message.
      CONCATENATE 'Error updating inactive program directory for' i_program ':'
                  lv_t100_message
             INTO rv_message SEPARATED BY space.
    ENDIF.

  ENDMETHOD.


  METHOD syntax_check.

    DATA lv_message TYPE string.
    DATA lv_line TYPE i.
    DATA lv_line_text TYPE string.
    DATA lv_word TYPE string.

    SYNTAX-CHECK FOR it_source
      MESSAGE lv_message
      LINE lv_line
      WORD lv_word.

    IF sy-subrc <> 0.
      lv_line_text = lv_line.
      CONCATENATE 'Syntax error before save: line' lv_line_text
                  ', word' lv_word ':'
                  lv_message
             INTO rv_message SEPARATED BY space.
    ENDIF.

  ENDMETHOD.


  METHOD verify_inactive_source.

    DATA lt_saved TYPE tt_source.
    DATA lt_active TYPE tt_source.
    DATA lv_active_subrc TYPE sy-subrc.
    DATA lv_saved_lines TYPE i.
    DATA lv_active_lines TYPE i.
    DATA lv_equal_text TYPE string.
    DATA lv_subrc_text TYPE string.
    DATA lv_lines_text TYPE string.

    READ REPORT i_program INTO lt_saved STATE 'I'.
    lv_subrc_text = sy-subrc.
    DESCRIBE TABLE lt_saved LINES lv_saved_lines.
    lv_lines_text = lv_saved_lines.
    CONCATENATE mv_last_log
                cl_abap_char_utilities=>newline
                'READ REPORT STATE I subrc:' lv_subrc_text
                ', lines:' lv_lines_text
           INTO mv_last_log SEPARATED BY space.
    IF sy-subrc <> 0.
      CONCATENATE 'Program' i_program
                  'was written, but inactive source cannot be read back.'
             INTO rv_message SEPARATED BY space.
      RETURN.
    ENDIF.

    lv_equal_text = xsdbool( lt_saved = it_source ).
    CONCATENATE mv_last_log
                cl_abap_char_utilities=>newline
                'Inactive source equals proposed source:' lv_equal_text
           INTO mv_last_log SEPARATED BY space.
    IF lt_saved <> it_source.
      CONCATENATE 'Program' i_program
                  'was written, but inactive source differs from proposed source.'
             INTO rv_message SEPARATED BY space.
      RETURN.
    ENDIF.

    READ REPORT i_program INTO lt_active STATE 'A'.
    lv_active_subrc = sy-subrc.
    lv_subrc_text = lv_active_subrc.
    DESCRIBE TABLE lt_active LINES lv_active_lines.
    lv_lines_text = lv_active_lines.
    CONCATENATE mv_last_log
                cl_abap_char_utilities=>newline
                'READ REPORT STATE A subrc:' lv_subrc_text
                ', lines:' lv_lines_text
           INTO mv_last_log SEPARATED BY space.
    lv_equal_text = xsdbool( lt_active = it_source ).
    CONCATENATE mv_last_log
                cl_abap_char_utilities=>newline
                'Active source equals proposed source:' lv_equal_text
           INTO mv_last_log SEPARATED BY space.
    lv_equal_text = xsdbool( lt_active = lt_saved ).
    CONCATENATE mv_last_log
                cl_abap_char_utilities=>newline
                'Active source equals inactive source:' lv_equal_text
           INTO mv_last_log SEPARATED BY space.

    IF i_existed = abap_true
    AND lv_active_subrc = 0
    AND lt_active = it_source.
      CONCATENATE 'No SE38 delta for' i_program
                  ': proposed source is identical to active source.'
             INTO rv_message SEPARATED BY space.
      RETURN.
    ENDIF.

    IF i_existed = abap_true
    AND lv_active_subrc = 0
    AND lt_active = lt_saved.
      CONCATENATE 'No SE38 delta for' i_program
                  ': inactive source is still identical to active source.'
             INTO rv_message SEPARATED BY space.
    ENDIF.

  ENDMETHOD.


  METHOD save_method.

    DATA lv_include   TYPE syrepid.
    DATA ls_mtdkey    TYPE seocpdkey.
    DATA lt_source    TYPE tt_source.
    DATA lv_t100_msg  TYPE string.

    CLEAR mv_last_log.

    IF i_class IS INITIAL OR i_method IS INITIAL.
      rv_message = |Method name is incomplete: class={ i_class } method={ i_method }.|.
      mv_last_log = rv_message.
      RETURN.
    ENDIF.

    lt_source = source_to_table( i_source ).
    IF lt_source IS INITIAL.
      rv_message = |No source code to save for method { i_class }=>{ i_method }.|.
      mv_last_log = rv_message.
      RETURN.
    ENDIF.

    ls_mtdkey-clsname = i_class.
    ls_mtdkey-cpdname = i_method.

    " Get include name for the method
    cl_oo_classname_service=>get_method_include(
      EXPORTING
        mtdkey              = ls_mtdkey
      RECEIVING
        result              = lv_include
      EXCEPTIONS
        method_not_existing = 1 ).

    IF sy-subrc <> 0 OR lv_include IS INITIAL.
      rv_message = |Method { i_class }=>{ i_method } not found. Cannot determine include.|.
      mv_last_log = rv_message.
      RETURN.
    ENDIF.

    mv_last_log = |SAVE_METHOD diagnostics|
               && cl_abap_char_utilities=>newline
               && |Object: METH { i_class }=>{ i_method }|
               && cl_abap_char_utilities=>newline
               && |Include: { lv_include }|
               && cl_abap_char_utilities=>newline
               && |Source lines: { lines( lt_source ) }|.

    " Write source into method include
    INSERT REPORT lv_include FROM lt_source STATE 'I'.
    IF sy-subrc <> 0.
      rv_message = |Error writing include { lv_include } for method { i_class }=>{ i_method }.|.
      mv_last_log = mv_last_log && cl_abap_char_utilities=>newline && rv_message.
      RETURN.
    ENDIF.

    mv_last_log = mv_last_log
               && cl_abap_char_utilities=>newline
               && |INSERT REPORT { lv_include } executed.|.

    " Activate via class pool
    DATA(lv_classpool) = cl_oo_classname_service=>get_classpool_name( i_class ).
    DATA(lv_act_msg) = activate_program( lv_classpool ).
    IF lv_act_msg IS NOT INITIAL.
      rv_message = lv_act_msg.
      mv_last_log = mv_last_log && cl_abap_char_utilities=>newline && rv_message.
      RETURN.
    ENDIF.

    mv_last_log = mv_last_log
               && cl_abap_char_utilities=>newline
               && |Class { i_class } activated via { lv_classpool }.|.

    rv_message = |Method { i_class }=>{ i_method } was saved and activated.|.
    mv_last_log = mv_last_log && cl_abap_char_utilities=>newline && rv_message.

  ENDMETHOD.
ENDCLASS.

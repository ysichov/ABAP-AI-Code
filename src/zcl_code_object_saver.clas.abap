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
protected section.
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

    CLASS-METHODS save_class
      IMPORTING
        i_class   TYPE string
        i_source  TYPE string
      RETURNING
        VALUE(rv_message) TYPE string.

    CLASS-METHODS save_method
      IMPORTING
        i_class   TYPE string
        i_method  TYPE string
        i_source  TYPE string
      RETURNING
        VALUE(rv_message) TYPE string.

    " Guarantees that the source for a method include is wrapped in exactly one
    " 'METHOD <name>. ... ENDMETHOD.' block. A method include is INCLUDEd verbatim
    " into the generated class pool, so a missing/duplicated wrapper breaks the
    " whole class. Accepts a body with or without an existing wrapper.
    CLASS-METHODS ensure_method_wrapper
      IMPORTING
        i_method  TYPE string
        it_source TYPE tt_source
      RETURNING
        VALUE(rt_source) TYPE tt_source.

    " Final consistency / syntax check of the whole class after saving.
    CLASS-METHODS verify_class
      IMPORTING
        iv_class TYPE seoclsname
      RETURNING
        VALUE(rv_error) TYPE string.

    " --- Whole-class source handling (robust path) ---------------------------
    " Reads the complete active source of a class (definition + implementation)
    " via the standard CL_OO_FACTORY API.
    CLASS-METHODS read_class_source
      IMPORTING
        iv_class       TYPE seoclsname
      RETURNING
        VALUE(rt_lines) TYPE string_table.

    " Writes the complete class source back (lock/set_source/save/unlock).
    CLASS-METHODS write_class_source
      IMPORTING
        iv_class       TYPE seoclsname
        it_lines       TYPE string_table
      RETURNING
        VALUE(rv_error) TYPE string.

    " Activates a class as a whole (NOT the individual REPS includes).
    CLASS-METHODS activate_class
      IMPORTING
        iv_class       TYPE seoclsname
      RETURNING
        VALUE(rv_error) TYPE string.

    " Replaces the body of one method (METHOD..ENDMETHOD) inside the full class
    " source. Returns whether the method was found.
    CLASS-METHODS replace_method_in_lines
      IMPORTING
        iv_method      TYPE string
        it_body        TYPE tt_source
      CHANGING
        ct_lines       TYPE string_table
      RETURNING
        VALUE(rv_found) TYPE abap_bool.

    " Adds a new method implementation (METHOD..ENDMETHOD) right before the last
    " ENDCLASS (the one closing the IMPLEMENTATION part). Used when a brand-new
    " method is declared in a section but has no implementation yet.
    CLASS-METHODS add_method_in_lines
      IMPORTING
        it_body        TYPE tt_source
      CHANGING
        ct_lines       TYPE string_table
      RETURNING
        VALUE(rv_added) TYPE abap_bool.

    " Replaces one section region (PUBLIC/PROTECTED/PRIVATE) inside the full
    " class definition. Returns whether the section was found.
    CLASS-METHODS replace_section_in_lines
      IMPORTING
        iv_section     TYPE string
        it_body        TYPE tt_source
      CHANGING
        ct_lines       TYPE string_table
      RETURNING
        VALUE(rv_found) TYPE abap_bool.

    " Extracts the clean section body (from "<sec> SECTION." up to, but not
    " including, the next section keyword / ENDCLASS / CLASS..IMPLEMENTATION)
    " out of a possibly messy parsed block.
    CLASS-METHODS clean_section_body
      IMPORTING
        iv_section     TYPE string
        it_block       TYPE tt_source
      RETURNING
        VALUE(rt_body) TYPE tt_source.
ENDCLASS.



CLASS ZCL_CODE_OBJECT_SAVER IMPLEMENTATION.


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
      WHEN 'REPS' OR 'PROG' OR 'PROGRAM' OR 'REPORT'.
        rv_message = save_program(
          i_program = i_object_name
          i_source  = i_source
          i_package = i_package ).
      WHEN 'CLASS' OR 'CLAS'.
        rv_message = save_class(
          i_class  = i_object_name
          i_source = i_source ).
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


  METHOD save_class.

    DATA lv_class   TYPE seoclsname.
    DATA lv_nl      TYPE string.
    DATA lt_cur     TYPE string_table.
    DATA lt_new     TYPE string_table.
    DATA lt_body    TYPE tt_source.
    DATA lv_want    TYPE string.
    DATA lv_found   TYPE abap_bool.
    DATA lv_err     TYPE string.

    CLEAR mv_last_log.
    lv_nl = cl_abap_char_utilities=>newline.

    lv_class = i_class.
    TRANSLATE lv_class TO UPPER CASE.
    CONDENSE lv_class.
    IF lv_class IS INITIAL.
      rv_message = 'Class name is empty.'.
      mv_last_log = rv_message.
      RETURN.
    ENDIF.

    mv_last_log = |SAVE_CLASS diagnostics| && lv_nl && |Object: CLAS { lv_class }|.

    " 1) Read the authoritative current full source (definition + implementation).
    "    All edits are applied on top of this, so untouched parts stay byte-exact.
    lt_cur = read_class_source( lv_class ).
    IF lt_cur IS INITIAL.
      rv_message = |Error saving class { lv_class }: cannot read source (locked, missing, or not active?).|.
      mv_last_log = mv_last_log && lv_nl && rv_message.
      RETURN.
    ENDIF.
    lt_new = lt_cur.

    " 2) Parse the proposed source into --- title --- blocks
    "    Titles: Public/Protected/Private Section, Method <name>
    DATA lv_rest TYPE string.
    lv_rest = i_source.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN lv_rest WITH lv_nl.

    TYPES: BEGIN OF ty_block,
             title  TYPE string,
             source TYPE string,
           END OF ty_block.
    DATA lt_blocks TYPE STANDARD TABLE OF ty_block WITH NON-UNIQUE DEFAULT KEY.
    DATA ls_block  LIKE LINE OF lt_blocks.

    DATA lt_lines TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
    SPLIT lv_rest AT lv_nl INTO TABLE lt_lines.

    CLEAR ls_block.
    LOOP AT lt_lines INTO DATA(lv_line).
      DATA(lv_line_upper) = lv_line.
      TRANSLATE lv_line_upper TO UPPER CASE.
      CONDENSE lv_line_upper.
      IF lv_line_upper CP '--- * ---'.
        IF ls_block-title IS NOT INITIAL.
          APPEND ls_block TO lt_blocks.
        ENDIF.
        CLEAR ls_block.
        DATA(lv_title_raw) = lv_line.
        REPLACE FIRST OCCURRENCE OF REGEX '^---\s*' IN lv_title_raw WITH ''.
        REPLACE FIRST OCCURRENCE OF REGEX '\s*---\s*$' IN lv_title_raw WITH ''.
        CONDENSE lv_title_raw.
        ls_block-title = lv_title_raw.
      ELSE.
        IF ls_block-title IS NOT INITIAL.
          IF ls_block-source IS NOT INITIAL.
            ls_block-source = ls_block-source && lv_nl.
          ENDIF.
          ls_block-source = ls_block-source && lv_line.
        ENDIF.
      ENDIF.
    ENDLOOP.
    IF ls_block-title IS NOT INITIAL.
      APPEND ls_block TO lt_blocks.
    ENDIF.

    IF lt_blocks IS INITIAL.
      rv_message = |No --- section/method --- blocks found for class { lv_class }.|.
      mv_last_log = mv_last_log && lv_nl && rv_message.
      RETURN.
    ENDIF.

    mv_last_log = mv_last_log && lv_nl && |Parsed { lines( lt_blocks ) } blocks.|.

    " 3) Apply each block onto the working copy of the full source
    LOOP AT lt_blocks INTO ls_block.
      DATA(lv_blk_upper) = ls_block-title.
      TRANSLATE lv_blk_upper TO UPPER CASE.
      CONDENSE lv_blk_upper.

      IF lv_blk_upper CP 'METHOD *'.
        DATA(lv_meth_name) = ls_block-title.
        REPLACE FIRST OCCURRENCE OF REGEX '^METHOD\s+' IN lv_meth_name WITH '' IGNORING CASE.
        CONDENSE lv_meth_name.

        lt_body = ensure_method_wrapper( i_method  = lv_meth_name
                                         it_source = source_to_table( ls_block-source ) ).

        lv_found = replace_method_in_lines( EXPORTING iv_method = lv_meth_name
                                                      it_body   = lt_body
                                            CHANGING  ct_lines  = lt_new ).
        IF lv_found = abap_true.
          mv_last_log = mv_last_log && lv_nl && |Method { lv_meth_name } applied.|.
        ELSE.
          " New method: not in the implementation yet -> add it before ENDCLASS.
          " The matching declaration is added by the corresponding section block.
          IF add_method_in_lines( EXPORTING it_body  = lt_body
                                  CHANGING  ct_lines = lt_new ) = abap_true.
            mv_last_log = mv_last_log && lv_nl && |Method { lv_meth_name } added (new implementation).|.
          ELSE.
            mv_last_log = mv_last_log && lv_nl && |Method { lv_meth_name } could not be added.|.
          ENDIF.
        ENDIF.

      ELSEIF lv_blk_upper CP '*SECTION*'.
        lv_want = COND string(
          WHEN lv_blk_upper CP '*PUBLIC*'    THEN 'PUBLIC'
          WHEN lv_blk_upper CP '*PROTECTED*' THEN 'PROTECTED'
          WHEN lv_blk_upper CP '*PRIVATE*'   THEN 'PRIVATE'
          ELSE '' ).
        IF lv_want IS INITIAL.
          CONTINUE.
        ENDIF.

        lt_body = clean_section_body( iv_section = lv_want
                                      it_block   = source_to_table( ls_block-source ) ).
        IF lt_body IS INITIAL.
          CONTINUE.
        ENDIF.

        lv_found = replace_section_in_lines( EXPORTING iv_section = lv_want
                                                       it_body    = lt_body
                                             CHANGING  ct_lines   = lt_new ).
        IF lv_found = abap_true.
          mv_last_log = mv_last_log && lv_nl && |{ lv_want } section applied.|.
        ENDIF.
      ENDIF.
    ENDLOOP.

    " 4) Nothing actually changed?
    IF lt_new = lt_cur.
      rv_message = |Class { lv_class }: no changes detected.|.
      mv_last_log = mv_last_log && lv_nl && rv_message.
      RETURN.
    ENDIF.

    " 5) Write the whole class source back as one consistent unit
    lv_err = write_class_source( iv_class = lv_class it_lines = lt_new ).
    IF lv_err IS NOT INITIAL.
      rv_message = lv_err.
      mv_last_log = mv_last_log && lv_nl && rv_message.
      RETURN.
    ENDIF.

    " 6) Activate the class as a whole
    lv_err = activate_class( lv_class ).
    IF lv_err IS NOT INITIAL.
      " Activation failed -> rollback to original source
      mv_last_log = mv_last_log && lv_nl && |Activation failed, rolling back...|.
      write_class_source( iv_class = lv_class it_lines = lt_cur ).
      activate_class( lv_class ).
      rv_message = |Error saving class { lv_class }: { lv_err } (rolled back to previous version).|.
      mv_last_log = mv_last_log && lv_nl && rv_message.
      RETURN.
    ENDIF.

    " 7) Verify — if broken, rollback immediately so the class stays clean
    lv_err = verify_class( lv_class ).
    IF lv_err IS NOT INITIAL.
      mv_last_log = mv_last_log && lv_nl && |Syntax error detected, rolling back...|.
      write_class_source( iv_class = lv_class it_lines = lt_cur ).
      activate_class( lv_class ).
      rv_message = |Error saving class { lv_class }: { lv_err } (rolled back to previous version).|.
      mv_last_log = mv_last_log && lv_nl && rv_message.
      RETURN.
    ENDIF.

    rv_message = |Class { lv_class } saved and activated.|.
    mv_last_log = mv_last_log && lv_nl && rv_message.

  ENDMETHOD.


  METHOD verify_class.

    DATA ls_clskey      TYPE seoclskey.
    DATA lv_syntaxerror TYPE abap_bool.

    " Use the class-aware syntax check. A plain SYNTAX-CHECK FOR on the generated
    " class pool fails with a false "CLASS-POOL is only allowed in a class pool"
    " error, because the pool can only be checked inside a real class-pool context.
    ls_clskey-clsname = iv_class.

    CALL FUNCTION 'SEO_CLASS_CHECK_CLASSPOOL'
      EXPORTING
        clskey                       = ls_clskey
        suppress_error_popup         = abap_true
      IMPORTING
        syntaxerror                  = lv_syntaxerror
      EXCEPTIONS
        _internal_class_not_existing = 1
        error_message                = 2
        OTHERS                       = 3.
    IF sy-subrc <> 0.
      " The check itself could not run -> don't fail a successful save with a
      " false error (activation above already validated the class).
      RETURN.
    ENDIF.

    IF lv_syntaxerror = abap_true.
      rv_error = |Class { iv_class } has syntax errors after save (check in SE24/ADT).|.
    ENDIF.

  ENDMETHOD.


  METHOD read_class_source.

    DATA li_source TYPE REF TO if_oo_clif_source.
    DATA lt_rsw    TYPE rswsourcet.

    TRY.
        li_source = cl_oo_factory=>create_instance( )->create_clif_source(
          clif_name = iv_class
          version   = if_oo_clif_source=>co_version_active ).
        li_source->get_source( IMPORTING source = lt_rsw ).
      CATCH cx_root.
        CLEAR rt_lines.
        RETURN.
    ENDTRY.

    " rswsourcet is a table of STRING, so it is assignment-compatible
    rt_lines = lt_rsw.

  ENDMETHOD.


  METHOD write_class_source.

    DATA li_source TYPE REF TO if_oo_clif_source.
    DATA lt_rsw    TYPE rswsourcet.
    DATA lx_error  TYPE REF TO cx_root.

    " rswsourcet is a table of STRING, so it is assignment-compatible
    lt_rsw = it_lines.

    TRY.
        li_source = cl_oo_factory=>create_instance( )->create_clif_source(
          clif_name = iv_class ).
        li_source->lock( ).
        li_source->set_source( source = lt_rsw ).
        li_source->save( ).
        li_source->unlock( ).
      CATCH cx_oo_access_permission INTO DATA(lx_lock).
        " Class is locked (someone is editing it in SE24/ADT)
        rv_error = |Error saving class { iv_class }: locked - { lx_lock->get_text( ) }|.
      CATCH cx_root INTO lx_error.
        rv_error = |Error saving class { iv_class }: { lx_error->get_text( ) }|.
    ENDTRY.

    " Never leave the class locked after a failed save attempt
    IF rv_error IS NOT INITIAL AND li_source IS BOUND.
      TRY.
          li_source->unlock( ).
        CATCH cx_root ##NO_HANDLER.
      ENDTRY.
    ENDIF.

  ENDMETHOD.


  METHOD activate_class.

    DATA lt_objects TYPE STANDARD TABLE OF dwinactiv WITH NON-UNIQUE DEFAULT KEY.
    DATA ls_object  TYPE dwinactiv.
    DATA lv_msg     TYPE string.
    DATA lv_subrc   TYPE string.

    ls_object-object   = 'CLAS'.
    ls_object-obj_name = iv_class.
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

    IF sy-subrc <> 0 AND sy-subrc <> 2.
      IF sy-msgid IS NOT INITIAL.
        MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
          WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4 INTO lv_msg.
      ELSE.
        lv_subrc = sy-subrc.
        lv_msg = |subrc { lv_subrc }|.
      ENDIF.
      rv_error = |Error activating class { iv_class }: { lv_msg }|.
    ENDIF.

  ENDMETHOD.


  METHOD replace_method_in_lines.

    DATA lv_start TYPE i.
    DATA lv_end   TYPE i.
    DATA lv_index TYPE i.
    DATA lv_upper TYPE string.
    DATA lt_new   TYPE string_table.
    DATA lv_line  TYPE string.

    " Locate "METHOD <name>." (case-insensitive, ignoring leading spaces)
    LOOP AT ct_lines INTO lv_line.
      lv_index = sy-tabix.
      lv_upper = lv_line.
      CONDENSE lv_upper.
      TRANSLATE lv_upper TO UPPER CASE.
      " Match "METHOD <name>." with optional spaces and trailing comment
      IF matches( val   = lv_upper
                  regex = |METHOD { to_upper( iv_method ) }\\s*\\.(\\s.*)?| ).
        lv_start = lv_index.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_start = 0.
      rv_found = abap_false.
      RETURN.
    ENDIF.

    " Locate the matching ENDMETHOD.
    lv_index = lv_start.
    WHILE lv_index <= lines( ct_lines ).
      lv_line = ct_lines[ lv_index ].
      lv_upper = lv_line.
      CONDENSE lv_upper.
      TRANSLATE lv_upper TO UPPER CASE.
      IF lv_upper CP 'ENDMETHOD*'.
        lv_end = lv_index.
        EXIT.
      ENDIF.
      lv_index = lv_index + 1.
    ENDWHILE.

    IF lv_end = 0.
      rv_found = abap_false.
      RETURN.
    ENDIF.

    " Rebuild: keep lines before start, insert new body, keep lines after end
    LOOP AT ct_lines INTO lv_line FROM 1 TO lv_start - 1.
      APPEND lv_line TO lt_new.
    ENDLOOP.
    LOOP AT it_body INTO DATA(lv_body_line).
      APPEND CONV string( lv_body_line ) TO lt_new.
    ENDLOOP.
    LOOP AT ct_lines INTO lv_line FROM lv_end + 1 TO lines( ct_lines ).
      APPEND lv_line TO lt_new.
    ENDLOOP.

    ct_lines = lt_new.
    rv_found = abap_true.

  ENDMETHOD.


  METHOD add_method_in_lines.

    DATA lv_last  TYPE i.
    DATA lv_index TYPE i.
    DATA lv_upper TYPE string.
    DATA lt_new   TYPE string_table.
    DATA lv_line  TYPE string.

    " Find the LAST ENDCLASS (closes CLASS ... IMPLEMENTATION)
    LOOP AT ct_lines INTO lv_line.
      lv_upper = lv_line.
      CONDENSE lv_upper.
      TRANSLATE lv_upper TO UPPER CASE.
      IF lv_upper CP 'ENDCLASS*'.
        lv_last = sy-tabix.
      ENDIF.
    ENDLOOP.

    IF lv_last = 0.
      rv_added = abap_false.
      RETURN.
    ENDIF.

    " Insert the new method body just before that ENDCLASS
    LOOP AT ct_lines INTO lv_line FROM 1 TO lv_last - 1.
      APPEND lv_line TO lt_new.
    ENDLOOP.
    APPEND `` TO lt_new. " blank separator
    LOOP AT it_body INTO DATA(lv_body_line).
      APPEND CONV string( lv_body_line ) TO lt_new.
    ENDLOOP.
    LOOP AT ct_lines INTO lv_line FROM lv_last TO lines( ct_lines ).
      APPEND lv_line TO lt_new.
    ENDLOOP.

    ct_lines = lt_new.
    rv_added = abap_true.

  ENDMETHOD.


  METHOD replace_section_in_lines.

    DATA lv_start TYPE i.
    DATA lv_end   TYPE i.
    DATA lv_index TYPE i.
    DATA lv_upper TYPE string.
    DATA lt_new   TYPE string_table.
    DATA lv_line  TYPE string.

    " Locate "<section> SECTION."
    LOOP AT ct_lines INTO lv_line.
      lv_index = sy-tabix.
      lv_upper = lv_line.
      CONDENSE lv_upper.
      TRANSLATE lv_upper TO UPPER CASE.
      IF lv_upper CP |{ to_upper( iv_section ) } SECTION.*|.
        lv_start = lv_index.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_start = 0.
      rv_found = abap_false.
      RETURN.
    ENDIF.

    " Section region ends right before the next section keyword or the
    " definition-closing ENDCLASS.
    lv_index = lv_start + 1.
    lv_end   = lines( ct_lines ).
    WHILE lv_index <= lines( ct_lines ).
      lv_line = ct_lines[ lv_index ].
      lv_upper = lv_line.
      CONDENSE lv_upper.
      TRANSLATE lv_upper TO UPPER CASE.
      IF lv_upper CP 'PUBLIC SECTION.*'
      OR lv_upper CP 'PROTECTED SECTION.*'
      OR lv_upper CP 'PRIVATE SECTION.*'
      OR lv_upper CP 'ENDCLASS*'.
        lv_end = lv_index - 1.
        EXIT.
      ENDIF.
      lv_index = lv_index + 1.
    ENDWHILE.

    LOOP AT ct_lines INTO lv_line FROM 1 TO lv_start - 1.
      APPEND lv_line TO lt_new.
    ENDLOOP.
    LOOP AT it_body INTO DATA(lv_body_line).
      APPEND CONV string( lv_body_line ) TO lt_new.
    ENDLOOP.
    LOOP AT ct_lines INTO lv_line FROM lv_end + 1 TO lines( ct_lines ).
      APPEND lv_line TO lt_new.
    ENDLOOP.

    ct_lines = lt_new.
    rv_found = abap_true.

  ENDMETHOD.


  METHOD clean_section_body.

    DATA lv_started TYPE abap_bool.
    DATA lv_upper   TYPE string.

    LOOP AT it_block INTO DATA(lv_line).
      lv_upper = lv_line.
      CONDENSE lv_upper.
      TRANSLATE lv_upper TO UPPER CASE.

      IF lv_started = abap_false.
        IF lv_upper CP |{ to_upper( iv_section ) } SECTION.*|.
          lv_started = abap_true.
          APPEND lv_line TO rt_body.
        ENDIF.
        CONTINUE.
      ENDIF.

      " Stop at the next structural keyword
      IF lv_upper CP 'PUBLIC SECTION.*'
      OR lv_upper CP 'PROTECTED SECTION.*'
      OR lv_upper CP 'PRIVATE SECTION.*'
      OR lv_upper CP 'ENDCLASS*'
      OR lv_upper CP 'CLASS *IMPLEMENTATION*'.
        EXIT.
      ENDIF.

      APPEND lv_line TO rt_body.
    ENDLOOP.

  ENDMETHOD.


  METHOD save_method.

    DATA lv_class TYPE seoclsname.
    DATA lv_nl    TYPE string.
    DATA lt_cur   TYPE string_table.
    DATA lt_new   TYPE string_table.
    DATA lt_body  TYPE tt_source.
    DATA lv_err   TYPE string.

    CLEAR mv_last_log.
    lv_nl = cl_abap_char_utilities=>newline.

    IF i_class IS INITIAL OR i_method IS INITIAL.
      rv_message = |Method name is incomplete: class={ i_class } method={ i_method }.|.
      mv_last_log = rv_message.
      RETURN.
    ENDIF.

    lt_body = source_to_table( i_source ).
    IF lt_body IS INITIAL.
      rv_message = |No source code to save for method { i_class }=>{ i_method }.|.
      mv_last_log = rv_message.
      RETURN.
    ENDIF.

    lv_class = i_class.
    TRANSLATE lv_class TO UPPER CASE.
    CONDENSE lv_class.

    mv_last_log = |SAVE_METHOD diagnostics| && lv_nl
               && |Object: METH { lv_class }=>{ i_method }|.

    " The method body written into the class must be a complete
    " 'METHOD <name>. ... ENDMETHOD.' block.
    lt_body = ensure_method_wrapper( i_method  = i_method
                                     it_source = lt_body ).

    " Read current full source, replace just this one method, write back whole.
    " Everything else stays byte-exact, so the class can never be corrupted.
    lt_cur = read_class_source( lv_class ).
    IF lt_cur IS INITIAL.
      rv_message = |Error saving class { lv_class }: cannot read source (locked, missing, or not active?).|.
      mv_last_log = mv_last_log && lv_nl && rv_message.
      RETURN.
    ENDIF.
    lt_new = lt_cur.

    IF replace_method_in_lines( EXPORTING iv_method = i_method
                                          it_body   = lt_body
                                CHANGING  ct_lines  = lt_new ) = abap_false.
      rv_message = |Error saving method { lv_class }=>{ i_method }: not declared in class |
                && |(add the declaration first; a body-only edit cannot create a method).|.
      mv_last_log = mv_last_log && lv_nl && rv_message.
      RETURN.
    ENDIF.

    IF lt_new = lt_cur.
      rv_message = |Method { lv_class }=>{ i_method } unchanged - nothing to save.|.
      mv_last_log = mv_last_log && lv_nl && rv_message.
      RETURN.
    ENDIF.

    lv_err = write_class_source( iv_class = lv_class it_lines = lt_new ).
    IF lv_err IS NOT INITIAL.
      rv_message = lv_err.
      mv_last_log = mv_last_log && lv_nl && rv_message.
      RETURN.
    ENDIF.

    lv_err = activate_class( lv_class ).
    IF lv_err IS NOT INITIAL.
      mv_last_log = mv_last_log && lv_nl && |Activation failed, rolling back...|.
      write_class_source( iv_class = lv_class it_lines = lt_cur ).
      activate_class( lv_class ).
      rv_message = |Error saving method { lv_class }=>{ i_method }: { lv_err } (rolled back).|.
      mv_last_log = mv_last_log && lv_nl && rv_message.
      RETURN.
    ENDIF.

    lv_err = verify_class( lv_class ).
    IF lv_err IS NOT INITIAL.
      mv_last_log = mv_last_log && lv_nl && |Syntax error detected, rolling back...|.
      write_class_source( iv_class = lv_class it_lines = lt_cur ).
      activate_class( lv_class ).
      rv_message = |Error saving method { lv_class }=>{ i_method }: { lv_err } (rolled back).|.
      mv_last_log = mv_last_log && lv_nl && rv_message.
      RETURN.
    ENDIF.

    rv_message = |Method { lv_class }=>{ i_method } saved and activated.|.
    mv_last_log = mv_last_log && lv_nl && rv_message.

  ENDMETHOD.


  METHOD ensure_method_wrapper.

    DATA lv_in_method TYPE abap_bool.
    DATA lv_depth     TYPE i.
    DATA lt_body      TYPE tt_source.
    DATA lv_upper     TYPE string.
    DATA lv_line      LIKE LINE OF it_source.

    " Strip any --- Section/Method --- markers that the class processor may have added.
    DATA lt_filtered LIKE it_source.
    LOOP AT it_source INTO lv_line.
      lv_upper = lv_line.
      TRANSLATE lv_upper TO UPPER CASE.
      CONDENSE lv_upper.
      IF lv_upper CP '---*---'.
        CONTINUE.  " skip save_class section markers
      ENDIF.
      APPEND lv_line TO lt_filtered.
    ENDLOOP.

    " Extract the inner body if the source already carries a METHOD ... ENDMETHOD
    " block; otherwise treat the whole source as the body.
    LOOP AT lt_filtered INTO lv_line.
      lv_upper = lv_line.
      TRANSLATE lv_upper TO UPPER CASE.
      CONDENSE lv_upper.
      IF lv_in_method = abap_false.
        IF lv_upper CP 'METHOD *' OR lv_upper = 'METHOD'.
          lv_in_method = abap_true.
          lv_depth     = 1.
          CONTINUE. " skip the METHOD line itself
        ENDIF.
      ELSE.
        IF lv_upper CP 'METHOD *' OR lv_upper = 'METHOD'.
          lv_depth = lv_depth + 1.
        ENDIF.
        IF lv_upper CP 'ENDMETHOD*'.
          lv_depth = lv_depth - 1.
          IF lv_depth = 0.
            EXIT. " matching ENDMETHOD reached - body collected
          ENDIF.
        ENDIF.
        APPEND lv_line TO lt_body.
      ENDIF.
    ENDLOOP.

    IF lv_in_method = abap_false.
      " No wrapper found in the provided source - everything is the body
      lt_body = lt_filtered.
    ENDIF.

    " Rebuild the include with exactly one clean wrapper
    APPEND |METHOD { to_lower( i_method ) }.| TO rt_source.
    LOOP AT lt_body INTO lv_line.
      APPEND lv_line TO rt_source.
    ENDLOOP.
    APPEND |ENDMETHOD.| TO rt_source.

  ENDMETHOD.
ENDCLASS.

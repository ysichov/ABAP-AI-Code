CLASS zcl_ai_code_reader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_read_command,
        object_type TYPE string,
        object_name TYPE string,
        method_name TYPE string,
        raw_command TYPE string,
      END OF ty_read_command,
      tt_read_commands TYPE STANDARD TABLE OF ty_read_command WITH NON-UNIQUE DEFAULT KEY,
      tt_source        TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.

    CLASS-METHODS parse_read_commands
      IMPORTING i_text            TYPE string
      RETURNING VALUE(rt_commands) TYPE tt_read_commands.

    CLASS-METHODS resolve_read_commands
      IMPORTING i_text          TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS extract_read_command_text
      IMPORTING i_text          TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS read_program
      IMPORTING i_program      TYPE string
                i_object_type  TYPE string OPTIONAL
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS read_class
      IMPORTING i_class        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS read_method
      IMPORTING i_class        TYPE string
                i_method       TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    " Removes from a read_class( ) text all "--- Method NAME ---" blocks whose
    " name is not in it_methods. Sections and other blocks are kept untouched.
    " Call it only when specific methods were requested - not always needed.
    CLASS-METHODS remove_unrequested_methods
      IMPORTING i_class_text   TYPE string
                it_methods     TYPE tt_source
      RETURNING VALUE(rv_text) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS class_include_prefix
      IMPORTING i_class         TYPE string
      RETURNING VALUE(rv_prefix) TYPE string.

    CLASS-METHODS append_include_source
      IMPORTING i_include       TYPE progname
                i_title         TYPE string
      CHANGING  cv_text         TYPE string.

    CLASS-METHODS format_source
      IMPORTING it_source      TYPE tt_source
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS zcl_ai_code_reader IMPLEMENTATION.

  METHOD parse_read_commands.
    DATA lv_rest TYPE string.
    DATA lv_pos  TYPE i.
    DATA lv_end  TYPE i.

    lv_rest = i_text.
    REPLACE ALL OCCURRENCES OF REGEX '\{\s*READ' IN lv_rest WITH '{READ'.
    REPLACE ALL OCCURRENCES OF REGEX 'TADIR\s*:' IN lv_rest WITH 'TADIR:'.

    WHILE lv_rest CS '{READ'.
      FIND FIRST OCCURRENCE OF '{READ' IN lv_rest MATCH OFFSET lv_pos.
      lv_rest = substring( val = lv_rest off = lv_pos + 1 ).

      FIND FIRST OCCURRENCE OF '}' IN lv_rest MATCH OFFSET lv_end.
      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      DATA(lv_command) = substring( val = lv_rest len = lv_end ).
      lv_rest = substring( val = lv_rest off = lv_end + 1 ).

      DATA(lv_command_upper) = lv_command.
      TRANSLATE lv_command_upper TO UPPER CASE.

      DATA(ls_command) = VALUE ty_read_command(
        raw_command = |{ '{' }{ lv_command }{ '}' }| ).

      IF lv_command_upper CS 'READ TADIR:'.
        DATA(lv_tail) = lv_command.
        SHIFT lv_tail UP TO ':'.
        SHIFT lv_tail LEFT DELETING LEADING ':'.
        CONDENSE lv_tail.

        DATA lt_parts TYPE STANDARD TABLE OF string WITH NON-UNIQUE DEFAULT KEY.
        SPLIT lv_tail AT space INTO TABLE lt_parts.
        DELETE lt_parts WHERE table_line IS INITIAL.

        IF lines( lt_parts ) >= 2.
          ls_command-object_type = lt_parts[ 1 ].
          ls_command-object_name = lt_parts[ 2 ].
        ENDIF.
      ELSEIF lv_command_upper CS 'READ: CLASS'.
        DATA(lv_class) = lv_command.
        SHIFT lv_class UP TO '='.
        SHIFT lv_class LEFT DELETING LEADING '='.
        CONDENSE lv_class.
        ls_command-object_type = 'CLASS'.
        ls_command-object_name = lv_class.
      ELSEIF lv_command_upper CS 'READ METH'.
        DATA(lv_method_ref) = lv_command.
        REPLACE FIRST OCCURRENCE OF REGEX '^READ METH' IN lv_method_ref WITH ''.
        CONDENSE lv_method_ref.
        SPLIT lv_method_ref AT '=>' INTO ls_command-object_name ls_command-method_name.
        ls_command-object_type = 'METH'.
      ENDIF.

      TRANSLATE ls_command-object_type TO UPPER CASE.
      IF ls_command-object_name IS NOT INITIAL.
        APPEND ls_command TO rt_commands.
      ENDIF.
    ENDWHILE.
  ENDMETHOD.

  METHOD resolve_read_commands.
    DATA(lt_commands) = parse_read_commands( i_text ).

    " Drop METH commands whose class is also read in full by the same batch -
    " the class read already contains the method source.
    LOOP AT lt_commands INTO DATA(ls_meth_cmd) WHERE object_type = 'METH' OR object_type = 'METHOD'.
      DATA(lv_meth_idx) = sy-tabix.
      DATA(lv_meth_class) = ls_meth_cmd-object_name.
      TRANSLATE lv_meth_class TO UPPER CASE.
      CONDENSE lv_meth_class.
      LOOP AT lt_commands INTO DATA(ls_class_cmd)
        WHERE object_type = 'CLASS' OR object_type = 'CLAS'.
        DATA(lv_class_name) = ls_class_cmd-object_name.
        TRANSLATE lv_class_name TO UPPER CASE.
        CONDENSE lv_class_name.
        IF lv_class_name = lv_meth_class.
          DELETE lt_commands INDEX lv_meth_idx.
          EXIT.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    LOOP AT lt_commands INTO DATA(ls_command).
      DATA(lv_resolved) = VALUE string( ).

      " Wildcard - search TADIR regardless of object type
      IF ls_command-object_name CS '*' OR ls_command-object_name CS '+'.
        lv_resolved = read_program(
          i_program     = ls_command-object_name
          i_object_type = ls_command-object_type ).
      ELSE.
        CASE ls_command-object_type.
          WHEN 'REPS' OR 'PROG'.
            lv_resolved = read_program(
              i_program     = ls_command-object_name
              i_object_type = ls_command-object_type ).
          WHEN 'CLAS' OR 'CLASS'.
            lv_resolved = read_class( ls_command-object_name ).
          WHEN 'METH' OR 'METHOD'.
            lv_resolved = read_method(
              i_class  = ls_command-object_name
              i_method = ls_command-method_name ).
        ENDCASE.
      ENDIF.

      IF lv_resolved IS NOT INITIAL.
        IF rv_text IS NOT INITIAL.
          rv_text = rv_text && cl_abap_char_utilities=>newline && cl_abap_char_utilities=>newline.
        ENDIF.

        rv_text = rv_text && lv_resolved.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD extract_read_command_text.
    DATA(lt_commands) = parse_read_commands( i_text ).

    LOOP AT lt_commands INTO DATA(ls_command).
      IF rv_text IS NOT INITIAL.
        rv_text = rv_text && cl_abap_char_utilities=>newline.
      ENDIF.
      rv_text = rv_text && ls_command-raw_command.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_program.
    DATA lt_source TYPE tt_source.
    DATA lt_source_extended TYPE abaptxt255_tab.
    DATA lv_program TYPE progname.
    DATA lv_tadir_object TYPE tadir-object.
    DATA lv_source_state TYPE string.

    lv_program = i_program.
    TRANSLATE lv_program TO UPPER CASE.
    CONDENSE lv_program.

    " Wildcard search - return list from TADIR
    IF lv_program CS '*' OR lv_program CS '+'.
      DATA lv_like_pattern TYPE string.
      lv_like_pattern = lv_program.
      REPLACE ALL OCCURRENCES OF '*' IN lv_like_pattern WITH '%'.
      REPLACE ALL OCCURRENCES OF '+' IN lv_like_pattern WITH '_'.

      " Map requested type to TADIR object column values
      DATA lt_tadir_types TYPE RANGE OF trobjtype.
      DATA(lv_type_upper) = i_object_type.
      TRANSLATE lv_type_upper TO UPPER CASE.
      CASE lv_type_upper.
        WHEN 'PROG' OR 'PROGRAM' OR 'REPORT'.
          APPEND VALUE #( sign = 'I' option = 'EQ' low = 'PROG' ) TO lt_tadir_types.
          APPEND VALUE #( sign = 'I' option = 'EQ' low = 'REPS' ) TO lt_tadir_types.
        WHEN 'CLAS' OR 'CLASS'.
          APPEND VALUE #( sign = 'I' option = 'EQ' low = 'CLAS' ) TO lt_tadir_types.
        WHEN 'FUGR' OR 'FM' OR 'FUNC'.
          APPEND VALUE #( sign = 'I' option = 'EQ' low = 'FUGR' ) TO lt_tadir_types.
        WHEN OTHERS.
          " No filter - return all matching object names
      ENDCASE.

      DATA lt_tadir TYPE STANDARD TABLE OF tadir WITH NON-UNIQUE DEFAULT KEY.
      IF lt_tadir_types IS NOT INITIAL.
        SELECT object obj_name devclass
          FROM tadir
          INTO CORRESPONDING FIELDS OF TABLE lt_tadir
          WHERE pgmid    = 'R3TR'
            AND obj_name LIKE lv_like_pattern
            AND object IN lt_tadir_types
          ORDER BY object obj_name.
      ELSE.
        SELECT object obj_name devclass
          FROM tadir
          INTO CORRESPONDING FIELDS OF TABLE lt_tadir
          WHERE pgmid    = 'R3TR'
            AND obj_name LIKE lv_like_pattern
          ORDER BY object obj_name.
      ENDIF.

      IF lt_tadir IS INITIAL.
        rv_text = |No objects found in TADIR matching { lv_program }.|.
        RETURN.
      ENDIF.

      rv_text = |Objects matching { lv_program }:|.
      LOOP AT lt_tadir INTO DATA(ls_tadir).
        rv_text = rv_text
               && cl_abap_char_utilities=>newline
               && |{ ls_tadir-object } { ls_tadir-obj_name }|.
      ENDLOOP.
      RETURN.
    ENDIF.

    SELECT SINGLE object
      FROM tadir
      INTO lv_tadir_object
      WHERE pgmid = 'R3TR'
        AND obj_name = lv_program
        AND object = 'PROG'.
    IF sy-subrc <> 0.
      SELECT SINGLE object
        FROM tadir
        INTO lv_tadir_object
        WHERE pgmid = 'R3TR'
          AND obj_name = lv_program
          AND object = 'REPS'.
    ENDIF.

    READ REPORT lv_program INTO lt_source.
    IF sy-subrc <> 0.
      READ REPORT lv_program INTO lt_source STATE 'I'.
      IF sy-subrc <> 0.
        CALL FUNCTION 'RPY_PROGRAM_READ'
          EXPORTING
            program_name     = lv_program
            with_includelist = abap_false
            with_lowercase   = abap_true
          TABLES
            source_extended  = lt_source_extended
          EXCEPTIONS
            cancelled        = 1
            not_found        = 2
            permission_error = 3
            OTHERS           = 4.
        IF sy-subrc <> 0.
          rv_text = |Source for program { lv_program } was not found or cannot be read.|.
          IF lv_tadir_object IS NOT INITIAL.
            rv_text = rv_text
                   && cl_abap_char_utilities=>newline
                   && |TADIR object type: { lv_tadir_object }.|.
          ENDIF.
          RETURN.
        ENDIF.
        CLEAR lt_source.
        LOOP AT lt_source_extended INTO DATA(lv_source_line).
          APPEND CONV string( lv_source_line ) TO lt_source.
        ENDLOOP.
        lv_source_state = 'repository'.
      ELSE.
        lv_source_state = 'inactive'.
      ENDIF.
    ELSE.
      lv_source_state = 'active'.
    ENDIF.

    rv_text = format_source( lt_source ).
  ENDMETHOD.

  METHOD read_class.
    DATA ls_clskey TYPE seoclskey.
    DATA lv_class TYPE string.
    DATA lt_methods TYPE seop_methods_w_include.

    lv_class = i_class.
    TRANSLATE lv_class TO UPPER CASE.
    CONDENSE lv_class.
    ls_clskey-clsname = lv_class.

    CALL FUNCTION 'SEO_CLASS_GET_METHOD_INCLUDES'
      EXPORTING
        clskey                       = ls_clskey
      IMPORTING
        includes                     = lt_methods
      EXCEPTIONS
        _internal_class_not_existing = 1
        OTHERS                       = 2.

    IF sy-subrc <> 0.
      " Fallback: search TADIR with LIKE (normalize *-wildcards to SQL %)
      DATA(lv_like) = |%{ lv_class }%|.
      REPLACE ALL OCCURRENCES OF '*' IN lv_like WITH '%'.
      REPLACE ALL OCCURRENCES OF '+' IN lv_like WITH '_'.
      DATA lt_found TYPE STANDARD TABLE OF tadir WITH NON-UNIQUE DEFAULT KEY.
      SELECT object obj_name
        FROM tadir
        INTO CORRESPONDING FIELDS OF TABLE lt_found
        WHERE pgmid    = 'R3TR'
          AND object   = 'CLAS'
          AND obj_name LIKE lv_like
        ORDER BY obj_name.
      IF lt_found IS INITIAL.
        rv_text = |Class { lv_class } was not found.|.
      ELSE.
        rv_text = |Class { lv_class } not found exactly. Similar classes in TADIR:|.
        LOOP AT lt_found INTO DATA(ls_found).
          rv_text = rv_text && cl_abap_char_utilities=>newline
                             && |{ ls_found-object } { ls_found-obj_name }|.
        ENDLOOP.
      ENDIF.
      RETURN.
    ENDIF.

    DATA(lv_prefix) = class_include_prefix( lv_class ).

    append_include_source(
      EXPORTING
        i_include = CONV progname( lv_prefix && 'CU' )
        i_title   = 'Public section'
      CHANGING
        cv_text   = rv_text ).

    append_include_source(
      EXPORTING
        i_include = CONV progname( lv_prefix && 'CI' )
        i_title   = 'Private section'
      CHANGING
        cv_text   = rv_text ).

    append_include_source(
      EXPORTING
        i_include = CONV progname( lv_prefix && 'CO' )
        i_title   = 'Protected section'
      CHANGING
        cv_text   = rv_text ).

    LOOP AT lt_methods INTO DATA(ls_method).
      append_include_source(
        EXPORTING
          i_include = ls_method-incname
          i_title   = |Method { ls_method-cpdkey-cpdname }|
        CHANGING
          cv_text   = rv_text ).
    ENDLOOP.
  ENDMETHOD.

  METHOD read_method.
    DATA ls_clskey TYPE seoclskey.
    DATA lv_class  TYPE string.
    DATA lv_method TYPE seocpdname.
    DATA lt_methods TYPE seop_methods_w_include.

    lv_class = i_class.
    lv_method = i_method.
    TRANSLATE lv_class TO UPPER CASE.
    TRANSLATE lv_method TO UPPER CASE.
    CONDENSE lv_class.
    CONDENSE lv_method.
    ls_clskey-clsname = lv_class.

    IF lv_class IS INITIAL OR lv_method IS INITIAL.
      rv_text = |Method command is incomplete: class={ lv_class } method={ lv_method }.|.
      RETURN.
    ENDIF.

    CALL FUNCTION 'SEO_CLASS_GET_METHOD_INCLUDES'
      EXPORTING
        clskey                       = ls_clskey
      IMPORTING
        includes                     = lt_methods
      EXCEPTIONS
        _internal_class_not_existing = 1
        OTHERS                       = 2.

    IF sy-subrc <> 0.
      DATA(lv_meth_like) = |%{ lv_class }%|.
      DATA lt_meth_found TYPE STANDARD TABLE OF tadir WITH NON-UNIQUE DEFAULT KEY.
      SELECT object obj_name
        FROM tadir
        INTO CORRESPONDING FIELDS OF TABLE lt_meth_found
        WHERE pgmid    = 'R3TR'
          AND object   = 'CLAS'
          AND obj_name LIKE lv_meth_like
        ORDER BY obj_name.
      IF lt_meth_found IS INITIAL.
        rv_text = |Class { lv_class } was not found.|.
      ELSE.
        rv_text = |Class { lv_class } not found exactly. Similar classes in TADIR:|.
        LOOP AT lt_meth_found INTO DATA(ls_meth_found).
          rv_text = rv_text && cl_abap_char_utilities=>newline
                             && |{ ls_meth_found-object } { ls_meth_found-obj_name }|.
        ENDLOOP.
      ENDIF.
      RETURN.
    ENDIF.

    READ TABLE lt_methods INTO DATA(ls_method)
      WITH KEY cpdkey-cpdname = lv_method.
    IF sy-subrc <> 0.
      rv_text = |Method { lv_class }=>{ lv_method } was not found.|.
      RETURN.
    ENDIF.

    append_include_source(
      EXPORTING
        i_include = ls_method-incname
        i_title   = |Method { lv_method }|
      CHANGING
        cv_text   = rv_text ).
  ENDMETHOD.

  METHOD remove_unrequested_methods.
    DATA lt_lines TYPE tt_source.
    DATA lt_keep  TYPE tt_source.
    DATA lv_skip  TYPE abap_bool.

    IF it_methods IS INITIAL.
      rv_text = i_class_text.
      RETURN.
    ENDIF.

    " Uppercased lookup table of requested method names
    LOOP AT it_methods INTO DATA(lv_method).
      TRANSLATE lv_method TO UPPER CASE.
      CONDENSE lv_method.
      IF lv_method IS NOT INITIAL.
        APPEND lv_method TO lt_keep.
      ENDIF.
    ENDLOOP.
    IF lt_keep IS INITIAL.
      rv_text = i_class_text.
      RETURN.
    ENDIF.

    SPLIT i_class_text AT cl_abap_char_utilities=>newline INTO TABLE lt_lines.

    LOOP AT lt_lines INTO DATA(lv_line).
      DATA(lv_upper) = lv_line.
      TRANSLATE lv_upper TO UPPER CASE.
      CONDENSE lv_upper.

      IF lv_upper CP '--- METHOD * ---'.
        DATA(lv_name) = lv_upper.
        REPLACE FIRST OCCURRENCE OF REGEX '^---\s*METHOD\s+' IN lv_name WITH ''.
        REPLACE FIRST OCCURRENCE OF REGEX '\s*---\s*$' IN lv_name WITH ''.
        CONDENSE lv_name.
        READ TABLE lt_keep WITH KEY table_line = lv_name TRANSPORTING NO FIELDS.
        lv_skip = xsdbool( sy-subrc <> 0 ).
      ELSEIF lv_upper CP '---*---'.
        " Any other block marker (sections, locals, ...) ends the skipped region
        lv_skip = abap_false.
      ENDIF.

      IF lv_skip = abap_true.
        CONTINUE.
      ENDIF.

      IF rv_text IS NOT INITIAL.
        rv_text = rv_text && cl_abap_char_utilities=>newline.
      ENDIF.
      rv_text = rv_text && lv_line.
    ENDLOOP.
  ENDMETHOD.

  METHOD class_include_prefix.
    rv_prefix = i_class.
    TRANSLATE rv_prefix TO UPPER CASE.
    CONDENSE rv_prefix.

    WHILE strlen( rv_prefix ) < 30.
      rv_prefix = rv_prefix && '='.
    ENDWHILE.
  ENDMETHOD.

  METHOD append_include_source.
    DATA lt_source TYPE tt_source.

    READ REPORT i_include INTO lt_source.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " Use a clean section marker without the internal include name.
    " The old format "--- Public section (ZCL_FOO=====CU) ---" cluttered the
    " ABAP editor and leaked internal names to the LLM / user.
    cv_text = cv_text
           && cl_abap_char_utilities=>newline
           && cl_abap_char_utilities=>newline
           && |--- { i_title } ---|
           && cl_abap_char_utilities=>newline
           && format_source( lt_source ).
  ENDMETHOD.

  METHOD format_source.
    LOOP AT it_source INTO DATA(lv_line).
      IF rv_text IS NOT INITIAL.
        rv_text = rv_text && cl_abap_char_utilities=>newline.
      ENDIF.
      rv_text = rv_text && lv_line.
    ENDLOOP.
  ENDMETHOD.


ENDCLASS.
